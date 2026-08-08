import Foundation
import Testing

@testable import PlotterRuntime

@Suite("Context-bound boundary voice interaction")
struct VoiceInteractionTests {
  private let parser = BoundaryVoiceCommandParser()

  @Test("READY is accepted only while an armed side awaits confirmation")
  func readyIsContextBound() {
    for transcript in ["ready", "READY!", "  ReAdY.\n"] {
      #expect(parser.parse(transcript, in: .awaitingReady) == .ready)
      #expect(parser.parse(transcript, in: .moving) == nil)
    }
  }

  @Test("STOP is accepted only while the armed boundary jog is moving")
  func stopIsContextBound() {
    for transcript in ["stop", "STOP!", "  StOp,\n"] {
      #expect(parser.parse(transcript, in: .moving) == .stop)
      #expect(parser.parse(transcript, in: .awaitingReady) == nil)
    }
  }

  @Test("ambient, compound, and obsolete commands never become boundary commands")
  func unrelatedSpeechIsRejected() {
    let rejected: [(String, BoundaryVoiceContext)] = [
      ("", .awaitingReady),
      ("please ready", .awaitingReady),
      ("ready now", .awaitingReady),
      ("ready and stop", .awaitingReady),
      ("stop", .awaitingReady),
      ("ready", .moving),
      ("please stop", .moving),
      ("stop now", .moving),
      ("stop and ready", .moving),
      ("cancel jog", .moving),
      ("x plus", .moving),
      ("pen up", .moving),
      ("controller status", .moving),
    ]

    for (transcript, context) in rejected {
      #expect(parser.parse(transcript, in: context) == nil)
    }
  }

  @Test("transcript delivery retains only the newest pending value")
  func newestTranscriptOnly() async throws {
    let buffer = VoiceTranscriptBuffer()
    let stream = await buffer.stream()
    var iterator = stream.makeAsyncIterator()
    let utteranceID = UUID()

    for sequence in 1...3 {
      await buffer.yield(
        VoiceTranscript(
          utteranceID: utteranceID,
          sequence: UInt64(sequence),
          text: "partial \(sequence)",
          isFinal: sequence == 3,
          monotonicNanoseconds: UInt64(sequence)
        ))
    }

    let received = try #require(await iterator.next())
    #expect(received.sequence == 3)
    #expect(received.isFinal)
    #expect(received.utteranceID == utteranceID)
  }

  @Test("only exact partial STOP receives native reflex stability by default")
  func partialStabilityIsNarrow() {
    let stop = VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: " STOP! ",
      isFinal: false,
      monotonicNanoseconds: 1
    )
    let continueHypothesis = VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: "continue",
      isFinal: false,
      monotonicNanoseconds: 2
    )
    let final = VoiceTranscript(
      utteranceID: UUID(),
      sequence: 3,
      text: "continue",
      isFinal: true,
      monotonicNanoseconds: 3
    )

    #expect(stop.stability == .stablePartial)
    #expect(continueHypothesis.stability == .unstablePartial)
    #expect(final.stability == .final)
  }

  @Test("speech output is injectable without a native audio dependency")
  func injectableSpeechOutput() async {
    let output = RecordingVoiceSpeechOutput()
    await output.speak("Controller idle")
    await output.stopSpeaking()

    #expect(await output.messages == ["Controller idle"])
    #expect(await output.stopCount == 1)
  }

  @Test("quiet recognition intervals restart with a bounded delay")
  func quietRecognitionRecoveryIsNarrowAndBounded() {
    let noSpeech = VoiceRecognitionFailureSnapshot(
      domain: "kAFAssistantErrorDomain",
      code: 1_110,
      description: "No speech detected"
    )
    #expect(VoiceRecognitionRecoveryPolicy.disposition(for: noSpeech) == .restart)
    #expect(
      VoiceRecognitionRecoveryPolicy.restartDelayNanoseconds(afterConsecutiveFailure: 1)
        == 100_000_000
    )
    #expect(
      VoiceRecognitionRecoveryPolicy.restartDelayNanoseconds(afterConsecutiveFailure: 5)
        == 1_000_000_000
    )
    #expect(
      VoiceRecognitionRecoveryPolicy.restartDelayNanoseconds(afterConsecutiveFailure: 50)
        == 1_000_000_000
    )
  }

  @Test("unrelated recognition failures remain terminal")
  func unrelatedRecognitionFailureDoesNotRetry() {
    let denied = VoiceRecognitionFailureSnapshot(
      domain: "SFSpeechRecognizerErrorDomain",
      code: 203,
      description: "Recognition failed"
    )
    let sameCodeWrongDomain = VoiceRecognitionFailureSnapshot(
      domain: "DifferentDomain",
      code: 1_110,
      description: "Different failure"
    )

    #expect(VoiceRecognitionRecoveryPolicy.disposition(for: denied) == .fail)
    #expect(VoiceRecognitionRecoveryPolicy.disposition(for: sameCodeWrongDomain) == .fail)
  }
}

private actor RecordingVoiceSpeechOutput: VoiceSpeechOutput {
  private(set) var messages: [String] = []
  private(set) var stopCount = 0

  func speak(_ text: String) {
    messages.append(text)
  }

  func stopSpeaking() {
    stopCount += 1
  }
}
