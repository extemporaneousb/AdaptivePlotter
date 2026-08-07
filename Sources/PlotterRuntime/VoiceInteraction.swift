@preconcurrency import AVFoundation
import Foundation
import PlotterModel
@preconcurrency import Speech

public enum OperatorVoiceSessionDefaultsError: Error, Hashable, Sendable {
  case invalidXStep
  case invalidYStep
  case invalidFeed
}

/// The numeric values an operator has already made visible for this session.
/// Voice commands can use them, but cannot introduce an untyped controller command.
public struct OperatorVoiceSessionDefaults: Hashable, Sendable {
  public let xStepMM: Double
  public let yStepMM: Double
  public let feedMMPerMinute: Double

  public init(xStepMM: Double, yStepMM: Double, feedMMPerMinute: Double) throws {
    guard xStepMM.isFinite, xStepMM > 0 else {
      throw OperatorVoiceSessionDefaultsError.invalidXStep
    }
    guard yStepMM.isFinite, yStepMM > 0 else {
      throw OperatorVoiceSessionDefaultsError.invalidYStep
    }
    guard feedMMPerMinute.isFinite, feedMMPerMinute > 0 else {
      throw OperatorVoiceSessionDefaultsError.invalidFeed
    }
    self.xStepMM = xStepMM
    self.yStepMM = yStepMM
    self.feedMMPerMinute = feedMMPerMinute
  }
}

/// A deliberately closed voice-to-runtime boundary. There is no raw text,
/// G-code, byte payload, pen-down command, or safety override in this type.
public enum OperatorVoiceIntent: Hashable, Sendable {
  case relativeJog(RelativeJogRequest)
  case raisePen
  case requestStatus
  case cancelCurrentMotion

  public var isPriority: Bool {
    if case .cancelCurrentMotion = self { return true }
    return false
  }
}

public enum OperatorVoiceParseRejection: Hashable, Sendable {
  case multipleCommandsNotAllowed
  case invalidJogSyntax
  case invalidDistance(String)
  case invalidFeed(String)
  case penDownNotAvailable
  case unrecognizedCommand

  public var actionableDescription: String {
    switch self {
    case .multipleCommandsNotAllowed:
      return "Say one command at a time."
    case .invalidJogSyntax:
      return
        "Say an axis and direction, for example: x plus, or move y minus 0.5 at 60."
    case .invalidDistance(let value):
      return "The jog distance '\(value)' must be one finite number greater than zero."
    case .invalidFeed(let value):
      return "The jog feed '\(value)' must be one finite number greater than zero."
    case .penDownNotAvailable:
      return "Voice control cannot lower the pen. Use a direct typed operator control."
    case .unrecognizedCommand:
      return "No command matched. Say x plus, x minus, y plus, y minus, pen up, status, or stop."
    }
  }
}

/// Spoken rejection copy is deliberately separate from the detailed display
/// reason. These fixed messages contain no accepted voice-command examples, so
/// synthesizer output cannot teach the live recognizer a physical intent.
public enum OperatorVoiceSpokenFeedbackPolicy {
  public static func rejection(_ rejection: OperatorVoiceParseRejection) -> String {
    switch rejection {
    case .multipleCommandsNotAllowed:
      return "Voice request rejected. Give one instruction at a time."
    case .invalidJogSyntax:
      return "Voice request rejected. Check the displayed movement syntax."
    case .invalidDistance:
      return "Voice request rejected. Check the displayed movement distance."
    case .invalidFeed:
      return "Voice request rejected. Check the displayed movement feed."
    case .penDownNotAvailable:
      return "Voice request rejected. Voice lowering is unavailable."
    case .unrecognizedCommand:
      return "Voice request rejected. Check the displayed instruction list."
    }
  }

  public static let invalidSessionDefaults =
    "Voice request rejected. Enter valid movement values in the visible fields."

  public static let operationAlreadyInFlight =
    "Voice request refused. Wait for the current operation to finish."
}

public enum OperatorVoiceParseResult: Hashable, Sendable {
  case intent(OperatorVoiceIntent)
  case noCommand
  case rejected(OperatorVoiceParseRejection)

  public var acceptedIntent: OperatorVoiceIntent? {
    guard case .intent(let intent) = self else { return nil }
    return intent
  }

  public var priorityIntent: OperatorVoiceIntent? {
    guard case .intent(let intent) = self, intent.isPriority else { return nil }
    return intent
  }
}

public struct OperatorVoiceCommandParser: Sendable {
  private static let jogPattern = try! NSRegularExpression(
    pattern:
      #"^(?:(?:move|jog)\s+)?([xy])\s+(plus|positive|minus|negative)(?:\s+([^\s]+)(?:\s+(?:mm|millimeter|millimeters))?)?(?:\s+(?:at|feed)\s+([^\s]+)(?:\s+(?:mm/min|millimeter per minute|millimeters per minute))?)?$"#,
    options: []
  )

  private static let jogPrefixPattern = try! NSRegularExpression(
    pattern: #"^(?:(?:move|jog)\s+)?[xy]\s+(?:plus|positive|minus|negative)\b"#,
    options: []
  )

  public init() {}

  public static func parse(
    _ transcript: String,
    defaults: OperatorVoiceSessionDefaults
  ) -> OperatorVoiceParseResult {
    Self().parse(transcript, defaults: defaults)
  }

  /// Defaults-free fast path for the only command allowed to preempt normal
  /// final-transcript handling. Multi-command speech never reaches this path.
  public static func parsePriority(_ transcript: String) -> OperatorVoiceIntent? {
    Self().parsePriority(transcript)
  }

  public func parsePriority(_ transcript: String) -> OperatorVoiceIntent? {
    let command = normalized(transcript)
    guard !command.isEmpty, !hasMultipleCommandBoundary(command) else { return nil }
    switch command {
    case "stop", "cancel jog": return .cancelCurrentMotion
    default: return nil
    }
  }

  public func parse(
    _ transcript: String,
    defaults: OperatorVoiceSessionDefaults
  ) -> OperatorVoiceParseResult {
    let command = normalized(transcript)
    guard !command.isEmpty else { return .noCommand }

    if hasMultipleCommandBoundary(command) {
      return .rejected(.multipleCommandsNotAllowed)
    }

    if let priorityIntent = parsePriority(command) {
      return .intent(priorityIntent)
    }

    switch command {
    case "pen up", "raise pen", "raise the pen":
      return .intent(.raisePen)
    case "pen down", "lower pen", "lower the pen":
      return .rejected(.penDownNotAvailable)
    case "status", "machine status", "controller status", "report status":
      return .intent(.requestStatus)
    default:
      break
    }

    let range = NSRange(command.startIndex..<command.endIndex, in: command)
    guard let match = Self.jogPattern.firstMatch(in: command, range: range) else {
      if Self.jogPrefixPattern.firstMatch(in: command, range: range) != nil {
        return .rejected(.invalidJogSyntax)
      }
      return .rejected(.unrecognizedCommand)
    }

    guard let axis = capture(1, from: match, in: command),
      let direction = capture(2, from: match, in: command)
    else {
      return .rejected(.invalidJogSyntax)
    }

    let distanceText = capture(3, from: match, in: command)
    let feedText = capture(4, from: match, in: command)
    let defaultDistance = axis == "x" ? defaults.xStepMM : defaults.yStepMM

    let distance: Double
    if let distanceText {
      guard let parsed = Double(distanceText), parsed.isFinite, parsed > 0 else {
        return .rejected(.invalidDistance(distanceText))
      }
      distance = parsed
    } else {
      distance = defaultDistance
    }

    let feed: Double
    if let feedText {
      guard let parsed = Double(feedText), parsed.isFinite, parsed > 0 else {
        return .rejected(.invalidFeed(feedText))
      }
      feed = parsed
    } else {
      feed = defaults.feedMMPerMinute
    }

    let sign = (direction == "minus" || direction == "negative") ? -1.0 : 1.0
    let delta = try? Vector2<MachineSpace>(
      dx: axis == "x" ? sign * distance : 0,
      dy: axis == "y" ? sign * distance : 0
    )
    guard let delta else {
      return .rejected(.invalidDistance(distanceText ?? String(distance)))
    }
    return .intent(
      .relativeJog(RelativeJogRequest(delta: delta, feedMMPerMinute: feed)))
  }

  private func normalized(_ transcript: String) -> String {
    let lowercase = transcript.lowercased().replacingOccurrences(of: "−", with: "-")
    let trimmed = lowercase.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".?!")))
    return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  private func hasMultipleCommandBoundary(_ command: String) -> Bool {
    command.contains(" and ") || command.contains(" then ") || command.contains(";")
      || command.contains(",")
  }

  private func capture(
    _ index: Int,
    from match: NSTextCheckingResult,
    in text: String
  ) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
      return nil
    }
    return String(text[swiftRange])
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

public struct VoiceTranscript: Hashable, Sendable {
  /// Stable across every partial and final result from one recognizer cycle.
  /// Consumers use it to dispatch a priority stop at most once.
  public let utteranceID: UUID
  public let sequence: UInt64
  public let text: String
  public let isFinal: Bool
  public let monotonicNanoseconds: UInt64

  public init(
    utteranceID: UUID,
    sequence: UInt64,
    text: String,
    isFinal: Bool,
    monotonicNanoseconds: UInt64
  ) {
    self.utteranceID = utteranceID
    self.sequence = sequence
    self.text = text
    self.isFinal = isFinal
    self.monotonicNanoseconds = monotonicNanoseconds
  }
}

public struct VoiceInteractionSnapshot: Hashable, Sendable {
  public let authorization: VoiceAuthorizationState
  public let listeningState: VoiceListeningState
  public let recognitionPolicy: VoiceRecognitionPolicy
  public let latestTranscript: VoiceTranscript?

  public init(
    authorization: VoiceAuthorizationState,
    listeningState: VoiceListeningState,
    recognitionPolicy: VoiceRecognitionPolicy,
    latestTranscript: VoiceTranscript?
  ) {
    self.authorization = authorization
    self.listeningState = listeningState
    self.recognitionPolicy = recognitionPolicy
    self.latestTranscript = latestTranscript
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
/// the priority STOP listener. Recovery is deliberately narrow and applies a
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

  public init(
    locale: Locale = .current,
    recognitionPolicy: VoiceRecognitionPolicy = .onDeviceRequired
  ) {
    localeIdentifier = locale.identifier
    self.recognitionPolicy = recognitionPolicy
    audioEngine = AVAudioEngine()
    authorization = Self.currentAuthorizationState()
  }

  public func snapshot() -> VoiceInteractionSnapshot {
    VoiceInteractionSnapshot(
      authorization: authorization,
      listeningState: listeningState,
      recognitionPolicy: recognitionPolicy,
      latestTranscript: latestTranscript
    )
  }

  public func requestAuthorization() async -> VoiceAuthorizationState {
    listeningState = .requestingPermission
    authorization = await Self.obtainAuthorization()
    if authorization != .authorized {
      listeningState = .failed(.authorization(authorization))
    } else {
      listeningState = .stopped
    }
    return authorization
  }

  public func startListening() async {
    if listeningState == .listening { return }

    if authorization != .authorized {
      _ = await requestAuthorization()
    }
    guard authorization == .authorized else { return }

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
    let format = input.inputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      listeningState = .failed(.audioInputUnavailable)
      return
    }

    if !hasInputTap {
      input.installTap(onBus: 0, bufferSize: 1_024, format: format) {
        [audioRelay] buffer, _ in
        audioRelay.append(buffer)
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
