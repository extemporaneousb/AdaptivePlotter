@preconcurrency import AVFoundation
@preconcurrency import CoreAudio
import Foundation
@preconcurrency import Speech

/// Reflex speech remains scoped to an explicitly active exploration context.
/// Motion Preflight questions use `PreflightVoiceResponseParser` instead.
public enum BoundaryVoiceContext: Hashable, Sendable {
  case awaitingReady
  case moving
}

public enum BoundaryVoiceCommand: Hashable, Sendable {
  case ready
  case stop
}

public struct BoundaryVoiceCommandParser: Sendable {
  public init() {}

  public func parse(_ transcript: String, in context: BoundaryVoiceContext) -> BoundaryVoiceCommand? {
    let words = transcript
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
    let command = String(words)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    switch (context, command) {
    case (.awaitingReady, "ready"):
      return .ready
    case (.moving, "stop"):
      return .stop
    default:
      return nil
    }
  }
}

public enum VoiceAuthorizationState: String, Hashable, Sendable {
  case notDetermined
  case authorized
  case speechDenied
  case speechRestricted
  case microphoneDenied
  case microphoneRestricted
}

public enum VoiceRecognitionPolicy: String, Hashable, Sendable {
  /// The recognizer request is required to remain on-device. If the system
  /// cannot satisfy that requirement, recognition fails instead of silently
  /// using a service.
  case onDeviceRequired

  /// Allows Apple's speech framework to select its system recognition service.
  /// This is an explicit fallback policy, not a claim that recognition is local.
  case allowSystemServiceFallback
}

public enum VoiceInteractionError: Error, Hashable, Sendable {
  case authorization(VoiceAuthorizationState)
  case recognizerUnavailable(localeIdentifier: String)
  case audioInputUnavailable
  case audioEngine(String)
  case recognition(String)

  public var actionableDescription: String {
    switch self {
    case .authorization(.speechDenied):
      return "Speech recognition is denied. Allow it in System Settings, then start listening again."
    case .authorization(.speechRestricted):
      return "Speech recognition is restricted for this process."
    case .authorization(.microphoneDenied):
      return "Microphone access is denied. Allow it in System Settings, then start listening again."
    case .authorization(.microphoneRestricted):
      return "Microphone access is restricted for this process."
    case .authorization:
      return "Speech and microphone authorization are not yet available."
    case .recognizerUnavailable(let localeIdentifier):
      return "Speech recognition is unavailable for \(localeIdentifier). Try again after the system recognizer becomes available."
    case .audioInputUnavailable:
      return "No usable microphone input is available. Select a microphone and start listening again."
    case .audioEngine(let detail):
      return "Microphone capture failed: \(detail)"
    case .recognition(let detail):
      return "Speech recognition failed: \(detail)"
    }
  }
}

public enum VoiceListeningState: Hashable, Sendable {
  case stopped
  case requestingPermission
  case listening
  case failed(VoiceInteractionError)
}

public enum VoiceHypothesisStability: String, Hashable, Sendable {
  case unstablePartial
  case stablePartial
  case final
}

public struct VoiceTranscript: Hashable, Sendable {
  /// Stable across every partial and final result from one recognizer cycle.
  /// Consumers use it to dispatch a context-bound STOP at most once.
  public let utteranceID: UUID
  public let sequence: UInt64
  public let text: String
  public let isFinal: Bool
  /// Apple Speech does not expose a general partial-result stability bit.
  /// Exact single-token STOP is deliberately treated as a stable partial at
  /// this boundary because its only contextual authority is cancellation.
  /// Injected deterministic transcripts may explicitly mark another partial
  /// stable; native motion-producing phrases otherwise wait for a final result.
  public let stability: VoiceHypothesisStability
  public let monotonicNanoseconds: UInt64

  public init(
    utteranceID: UUID,
    sequence: UInt64,
    text: String,
    isFinal: Bool,
    stability: VoiceHypothesisStability? = nil,
    monotonicNanoseconds: UInt64
  ) {
    self.utteranceID = utteranceID
    self.sequence = sequence
    self.text = text
    self.isFinal = isFinal
    if isFinal {
      self.stability = .final
    } else if let stability {
      self.stability = stability == .final ? .unstablePartial : stability
    } else {
      self.stability = Self.normalized(text) == "stop" ? .stablePartial : .unstablePartial
    }
    self.monotonicNanoseconds = monotonicNanoseconds
  }

  private static func normalized(_ text: String) -> String {
    let characters = text
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
    return String(characters)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}

public struct VoiceInteractionSnapshot: Hashable, Sendable {
  public let authorization: VoiceAuthorizationState
  public let listeningState: VoiceListeningState
  public let recognitionPolicy: VoiceRecognitionPolicy
  public let latestTranscript: VoiceTranscript?
  public let inputDeviceName: String?
  /// Linear 0...1 microphone energy derived from recent input buffers. This is
  /// operator feedback only; it is not speech-recognition confidence.
  public let inputLevel: Double

  public init(
    authorization: VoiceAuthorizationState,
    listeningState: VoiceListeningState,
    recognitionPolicy: VoiceRecognitionPolicy,
    latestTranscript: VoiceTranscript?,
    inputDeviceName: String? = nil,
    inputLevel: Double = 0
  ) {
    self.authorization = authorization
    self.listeningState = listeningState
    self.recognitionPolicy = recognitionPolicy
    self.latestTranscript = latestTranscript
    self.inputDeviceName = inputDeviceName
    self.inputLevel = min(max(inputLevel, 0), 1)
  }
}

public protocol VoiceInteractionDriving: Sendable {
  func snapshot() async -> VoiceInteractionSnapshot
  func requestAuthorization() async -> VoiceAuthorizationState
  func startListening() async
  func stopListening() async
  func transcripts() async -> AsyncStream<VoiceTranscript>
}

actor VoiceTranscriptBuffer {
  private var continuations: [UUID: AsyncStream<VoiceTranscript>.Continuation] = [:]

  func stream() -> AsyncStream<VoiceTranscript> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      continuations[identifier] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.remove(identifier) }
      }
    }
  }

  func yield(_ transcript: VoiceTranscript) {
    for continuation in continuations.values {
      continuation.yield(transcript)
    }
  }

  private func remove(_ identifier: UUID) {
    continuations.removeValue(forKey: identifier)
  }
}

private final class VoiceAudioRequestRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?

  func replace(with request: SFSpeechAudioBufferRecognitionRequest) {
    lock.withLock { self.request = request }
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    request?.append(buffer)
    lock.unlock()
  }

  func endCurrent() {
    let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
      defer { self.request = nil }
      return self.request
    }
    request?.endAudio()
  }
}

enum VoiceInputLevelNormalizer {
  static func normalize(rms: Double) -> Double {
    guard rms.isFinite, rms > 0 else { return 0 }
    let decibels = 20 * log10(max(rms, 0.000_001))
    return min(max((decibels + 60) / 60, 0), 1)
  }
}

private final class VoiceInputMeterRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var level = 0.0

  func measure(_ buffer: AVAudioPCMBuffer) {
    guard let channels = buffer.floatChannelData else {
      lock.withLock { level = 0 }
      return
    }
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else {
      lock.withLock { level = 0 }
      return
    }

    var sumOfSquares = 0.0
    var sampleCount = 0
    for channel in 0..<channelCount {
      let samples = channels[channel]
      for frame in 0..<frameCount {
        let sample = Double(samples[frame])
        sumOfSquares += sample * sample
      }
      sampleCount += frameCount
    }
    let rms = sqrt(sumOfSquares / Double(sampleCount))
    // The visible meter spans -60 dBFS (quiet) through 0 dBFS (clipping).
    let normalized = VoiceInputLevelNormalizer.normalize(rms: rms)
    lock.withLock {
      // Fast attack and modest decay keep speech readable at the UI's 4 Hz poll.
      level = normalized >= level ? normalized : (level * 0.72 + normalized * 0.28)
    }
  }

  func snapshot() -> Double {
    lock.withLock { level }
  }

  func reset() {
    lock.withLock { level = 0 }
  }
}

struct VoiceRecognitionFailureSnapshot: Hashable, Sendable {
  let domain: String
  let code: Int
  let description: String
}

enum VoiceRecognitionRecoveryDisposition: Hashable, Sendable {
  case restart
  case fail
}

/// Apple Speech reports an ordinary quiet recognition interval as
/// kAFAssistantErrorDomain/1110. Treating that as terminal silently removes
/// the context-bound STOP listener. Recovery is deliberately narrow and applies a
/// bounded delay so a broken recognizer cannot create a tight restart loop.
enum VoiceRecognitionRecoveryPolicy {
  static func disposition(
    for failure: VoiceRecognitionFailureSnapshot
  ) -> VoiceRecognitionRecoveryDisposition {
    if failure.domain == "kAFAssistantErrorDomain", failure.code == 1_110 {
      return .restart
    }
    return .fail
  }

  static func restartDelayNanoseconds(afterConsecutiveFailure count: Int) -> UInt64 {
    let boundedCount = min(max(count, 1), 5)
    let delays: [UInt64] = [
      100_000_000,
      200_000_000,
      400_000_000,
      800_000_000,
      1_000_000_000,
    ]
    return delays[boundedCount - 1]
  }
}

private struct VoiceRecognitionCallbackSnapshot: Sendable {
  let generation: UUID
  let text: String?
  let isFinal: Bool
  let failure: VoiceRecognitionFailureSnapshot?
}

/// Speech framework callback objects are not Sendable. This bridge receives a
/// value-only snapshot made synchronously on the callback and then crosses the
/// actor boundary without retaining the driver through its recognition task.
private final class VoiceRecognitionCallbackBridge: @unchecked Sendable {
  private weak var driver: NativeVoiceInteractionDriver?

  init(driver: NativeVoiceInteractionDriver) {
    self.driver = driver
  }

  func deliver(_ snapshot: VoiceRecognitionCallbackSnapshot) {
    guard let driver else { return }
    Task { await driver.receive(snapshot) }
  }
}

/// Native macOS microphone and speech-recognition owner. Transcript fan-out is
/// bounded to the newest value for every consumer.
public actor NativeVoiceInteractionDriver: VoiceInteractionDriving {
  private let localeIdentifier: String
  private let recognitionPolicy: VoiceRecognitionPolicy
  private let audioEngine: AVAudioEngine
  private let audioRelay = VoiceAudioRequestRelay()
  private let inputMeterRelay = VoiceInputMeterRelay()
  private let transcriptBuffer = VoiceTranscriptBuffer()

  private var recognizer: SFSpeechRecognizer?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionRestartTask: Task<Void, Never>?
  private var recognitionGeneration: UUID?
  private var recognitionRestartToken: UUID?
  private var consecutiveTransientFailures = 0
  private var hasInputTap = false
  private var authorization: VoiceAuthorizationState
  private var listeningState: VoiceListeningState = .stopped
  private var latestTranscript: VoiceTranscript?
  private var transcriptSequence: UInt64 = 0
  private var lifecycleGeneration: UInt64 = 0
  private var listeningRequested = false
  private var inputDeviceName: String?

  public init(
    locale: Locale = .current,
    recognitionPolicy: VoiceRecognitionPolicy = .onDeviceRequired
  ) {
    localeIdentifier = locale.identifier
    self.recognitionPolicy = recognitionPolicy
    audioEngine = AVAudioEngine()
    authorization = Self.currentAuthorizationState()
    inputDeviceName = Self.defaultInputDeviceName()
  }

  public func snapshot() -> VoiceInteractionSnapshot {
    VoiceInteractionSnapshot(
      authorization: authorization,
      listeningState: listeningState,
      recognitionPolicy: recognitionPolicy,
      latestTranscript: latestTranscript,
      inputDeviceName: inputDeviceName,
      inputLevel: listeningState == .listening ? inputMeterRelay.snapshot() : 0
    )
  }

  public func requestAuthorization() async -> VoiceAuthorizationState {
    let generation = lifecycleGeneration
    listeningState = .requestingPermission
    let result = await Self.obtainAuthorization()
    authorization = result
    guard lifecycleGeneration == generation else { return result }
    if result != .authorized {
      listeningState = .failed(.authorization(result))
    } else {
      listeningState = .stopped
    }
    return result
  }

  public func startListening() async {
    if listeningState == .listening { return }

    lifecycleGeneration &+= 1
    let generation = lifecycleGeneration
    listeningRequested = true

    if authorization != .authorized {
      listeningState = .requestingPermission
      authorization = await Self.obtainAuthorization()
    }
    guard listeningRequested, lifecycleGeneration == generation else { return }
    guard authorization == .authorized else {
      listeningRequested = false
      listeningState = .failed(.authorization(authorization))
      return
    }

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
      recognizer.isAvailable
    else {
      listeningState = .failed(.recognizerUnavailable(localeIdentifier: localeIdentifier))
      return
    }
    self.recognizer = recognizer
    consecutiveTransientFailures = 0
    recognitionRestartToken = nil
    recognitionRestartTask?.cancel()
    recognitionRestartTask = nil

    let input = audioEngine.inputNode
    inputDeviceName = Self.defaultInputDeviceName()
    let format = input.inputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      listeningState = .failed(.audioInputUnavailable)
      return
    }

    if !hasInputTap {
      input.installTap(onBus: 0, bufferSize: 1_024, format: format) {
        [audioRelay, inputMeterRelay] buffer, _ in
        audioRelay.append(buffer)
        inputMeterRelay.measure(buffer)
      }
      hasInputTap = true
    }

    listeningState = .listening
    beginRecognitionCycle(using: recognizer)
    do {
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      stopAudioResources()
      listeningState = .failed(.audioEngine(String(describing: error)))
    }
  }

  public func stopListening() {
    listeningRequested = false
    lifecycleGeneration &+= 1
    stopAudioResources()
    listeningState = .stopped
  }

  public func transcripts() async -> AsyncStream<VoiceTranscript> {
    await transcriptBuffer.stream()
  }

  private func beginRecognitionCycle(using recognizer: SFSpeechRecognizer) {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognitionPolicy == .onDeviceRequired
    audioRelay.replace(with: request)

    let generation = UUID()
    recognitionGeneration = generation
    let callbackBridge = VoiceRecognitionCallbackBridge(driver: self)
    recognitionTask = recognizer.recognitionTask(with: request) { result, error in
      let failure = error.map { error -> VoiceRecognitionFailureSnapshot in
        let nsError = error as NSError
        return VoiceRecognitionFailureSnapshot(
          domain: nsError.domain,
          code: nsError.code,
          description: String(describing: error)
        )
      }
      callbackBridge.deliver(
        VoiceRecognitionCallbackSnapshot(
          generation: generation,
          text: result?.bestTranscription.formattedString,
          isFinal: result?.isFinal ?? false,
          failure: failure
        ))
    }
  }

  fileprivate func receive(_ callback: VoiceRecognitionCallbackSnapshot) async {
    guard recognitionGeneration == callback.generation, listeningState == .listening else {
      return
    }

    if let text = callback.text {
      consecutiveTransientFailures = 0
      transcriptSequence &+= 1
      let now = DispatchTime.now().uptimeNanoseconds
      let monotonic = max(now, (latestTranscript?.monotonicNanoseconds ?? 0) &+ 1)
      let transcript = VoiceTranscript(
        utteranceID: callback.generation,
        sequence: transcriptSequence,
        text: text,
        isFinal: callback.isFinal,
        monotonicNanoseconds: monotonic
      )
      latestTranscript = transcript
      await transcriptBuffer.yield(transcript)

      if callback.isFinal {
        recognitionTask = nil
        audioRelay.endCurrent()
        if let recognizer, recognizer.isAvailable {
          beginRecognitionCycle(using: recognizer)
        } else {
          stopAudioResources()
          listeningState = .failed(.recognizerUnavailable(localeIdentifier: localeIdentifier))
        }
      }
      return
    }

    if let failure = callback.failure {
      switch VoiceRecognitionRecoveryPolicy.disposition(for: failure) {
      case .restart:
        scheduleRecognitionRestart()
      case .fail:
        stopAudioResources()
        listeningState = .failed(.recognition(failure.description))
      }
    }
  }

  private func scheduleRecognitionRestart() {
    recognitionGeneration = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    audioRelay.endCurrent()

    consecutiveTransientFailures = min(consecutiveTransientFailures + 1, 5)
    let delay = VoiceRecognitionRecoveryPolicy.restartDelayNanoseconds(
      afterConsecutiveFailure: consecutiveTransientFailures
    )
    let token = UUID()
    recognitionRestartToken = token
    recognitionRestartTask?.cancel()
    recognitionRestartTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.resumeRecognition(after: token)
    }
  }

  private func resumeRecognition(after token: UUID) {
    guard recognitionRestartToken == token, listeningState == .listening else { return }
    recognitionRestartToken = nil
    recognitionRestartTask = nil
    guard let recognizer, recognizer.isAvailable else {
      stopAudioResources()
      listeningState = .failed(.recognizerUnavailable(localeIdentifier: localeIdentifier))
      return
    }
    beginRecognitionCycle(using: recognizer)
  }

  private func stopAudioResources() {
    recognitionGeneration = nil
    recognitionRestartToken = nil
    recognitionRestartTask?.cancel()
    recognitionRestartTask = nil
    consecutiveTransientFailures = 0
    recognitionTask?.cancel()
    recognitionTask = nil
    audioRelay.endCurrent()
    if audioEngine.isRunning { audioEngine.stop() }
    if hasInputTap {
      audioEngine.inputNode.removeTap(onBus: 0)
      hasInputTap = false
    }
    inputMeterRelay.reset()
  }

  private static func defaultInputDeviceName() -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &deviceIDSize,
      &deviceID
    ) == noErr,
      deviceID != kAudioObjectUnknown
    else { return nil }

    address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var unmanagedName: Unmanaged<CFString>?
    var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &nameSize,
      &unmanagedName
    ) == noErr,
      let unmanagedName
    else { return nil }
    return unmanagedName.takeUnretainedValue() as String
  }

  private static func currentAuthorizationState() -> VoiceAuthorizationState {
    combineAuthorization(
      speech: SFSpeechRecognizer.authorizationStatus(),
      microphone: AVCaptureDevice.authorizationStatus(for: .audio)
    )
  }

  private static func obtainAuthorization() async -> VoiceAuthorizationState {
    var speech = SFSpeechRecognizer.authorizationStatus()
    if speech == .notDetermined {
      speech = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
      }
    }

    var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    if microphone == .notDetermined {
      let granted = await AVCaptureDevice.requestAccess(for: .audio)
      microphone = granted ? .authorized : .denied
    }
    return combineAuthorization(speech: speech, microphone: microphone)
  }

  private static func combineAuthorization(
    speech: SFSpeechRecognizerAuthorizationStatus,
    microphone: AVAuthorizationStatus
  ) -> VoiceAuthorizationState {
    switch speech {
    case .denied: return .speechDenied
    case .restricted: return .speechRestricted
    case .notDetermined: return .notDetermined
    case .authorized: break
    @unknown default: return .speechRestricted
    }

    switch microphone {
    case .authorized: return .authorized
    case .denied: return .microphoneDenied
    case .restricted: return .microphoneRestricted
    case .notDetermined: return .notDetermined
    @unknown default: return .microphoneRestricted
    }
  }
}

public protocol VoiceSpeechOutput: Sendable {
  func speak(_ text: String) async
  func stopSpeaking() async
}

/// Spoken feedback is newest-only: a new message interrupts queued speech so
/// stale controller state cannot continue narrating over current state.
public actor NativeVoiceSpeechOutput: VoiceSpeechOutput {
  private let synthesizer = AVSpeechSynthesizer()
  private let voiceLanguage: String?

  public init(voiceLanguage: String? = nil) {
    self.voiceLanguage = voiceLanguage
  }

  public func speak(_ text: String) {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: message)
    if let voiceLanguage, let voice = AVSpeechSynthesisVoice(language: voiceLanguage) {
      utterance.voice = voice
    }
    synthesizer.speak(utterance)
  }

  public func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
