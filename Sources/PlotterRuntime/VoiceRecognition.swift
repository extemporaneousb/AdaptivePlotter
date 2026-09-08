@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

public enum SpeechInputEvent: Sendable {
  // Capture recognition time before delivery can queue behind UI work.
  case transcript(String, isFinal: Bool, observedAt: ContinuousClock.Instant = .now)
  case level(Float)
  case failed(String)
  case ended
}

/// Microphone input only. Interpreting a response belongs to the current UI
/// request surface; this service has no plotter or Learning dependencies.
@MainActor
public protocol SpeechListening: AnyObject {
  func start(contextualPhrases: [String]) async throws -> AsyncStream<SpeechInputEvent>
  func stop()
}

@MainActor
public final class NativeSpeechListener: SpeechListening {
  private var engine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognizer: SFSpeechRecognizer?
  private var recognition: SFSpeechRecognitionTask?
  private var continuation: AsyncStream<SpeechInputEvent>.Continuation?
  private var sessionID: UUID?

  public init() {}

  public func start(contextualPhrases: [String]) async throws -> AsyncStream<SpeechInputEvent> {
    stop()
    let id = UUID()
    sessionID = id
    let authorization = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard sessionID == id, !Task.isCancelled else { throw CancellationError() }
    guard authorization == .authorized else {
      throw VoiceInputError.unavailable("Allow Speech Recognition for AdaptivePlotter in System Settings → Privacy & Security.")
    }
    let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
    guard sessionID == id, !Task.isCancelled else { throw CancellationError() }
    guard microphoneAllowed else {
      throw VoiceInputError.unavailable("Allow Microphone access for AdaptivePlotter in System Settings → Privacy & Security.")
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
      throw VoiceInputError.unavailable("Speech recognition is currently unavailable. Retry Voice when the service is available.")
    }
    let engine = AVAudioEngine()
    let format = engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw VoiceInputError.unavailable("No microphone input is available. Select an input in Sound settings.")
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .confirmation
    request.contextualStrings = Array(contextualPhrases.prefix(100))
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    let (stream, continuation) = AsyncStream<SpeechInputEvent>.makeStream()
    // Never let meter updates evict a recognized Stop while the UI is busy.
    // Events contain text/scalars only; audio buffers are not retained here.
    self.recognizer = recognizer
    self.engine = engine
    self.request = request
    self.continuation = continuation
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor in
        if self?.sessionID == id { self?.stop() }
      }
    }
    let meter = SpeechInputMeter()
    engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
      request.append(buffer)
      if let level = meter.sample(buffer) { continuation.yield(.level(level)) }
    }
    recognition = recognizer.recognitionTask(with: request) { result, error in
      if let result {
        continuation.yield(.transcript(result.bestTranscription.formattedString, isFinal: result.isFinal))
      }
      if let error, result?.isFinal != true {
        continuation.yield(.failed(error.localizedDescription))
      } else if result?.isFinal == true {
        // The consumer orders Stop submission before microphone teardown.
        continuation.yield(.ended)
      }
    }
    do {
      engine.prepare()
      try engine.start()
    } catch {
      stop()
      throw error
    }
    return stream
  }

  public func stop() {
    sessionID = nil
    if let engine {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    engine = nil
    request?.endAudio()
    request = nil
    recognition?.cancel()
    recognition = nil
    recognizer = nil
    continuation?.finish()
    continuation = nil
  }
}

private enum VoiceInputError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    switch self { case .unavailable(let message): message }
  }
}

/// The audio callback owns buffer access; the lock protects only the meter's
/// sampling timestamp. No audio buffer or recording is retained.
private final class SpeechInputMeter: @unchecked Sendable {
  private let lock = NSLock()
  private var lastSample: UInt64 = 0

  func sample(_ buffer: AVAudioPCMBuffer) -> Float? {
    lock.lock()
    defer { lock.unlock() }
    let now = DispatchTime.now().uptimeNanoseconds
    guard now - lastSample >= 100_000_000,
      let samples = buffer.floatChannelData?[0], buffer.frameLength > 0
    else { return nil }
    lastSample = now
    var sum: Float = 0
    for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
    return min(1, sqrt(sum / Float(buffer.frameLength)) * 8)
  }
}
