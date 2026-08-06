import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Closed native voice interaction")
struct VoiceInteractionTests {
  private let parser = OperatorVoiceCommandParser()

  @Test("axis commands preserve independent session defaults")
  func independentAxisDefaults() throws {
    let defaults = try OperatorVoiceSessionDefaults(
      xStepMM: 0.25,
      yStepMM: 0.75,
      feedMMPerMinute: 40
    )

    #expect(
      parser.parse("x plus", defaults: defaults)
        == .intent(
          .relativeJog(
            RelativeJogRequest(
              delta: try Vector2<MachineSpace>(dx: 0.25, dy: 0),
              feedMMPerMinute: 40
            )))
    )
    #expect(
      parser.parse("move y minus", defaults: defaults)
        == .intent(
          .relativeJog(
            RelativeJogRequest(
              delta: try Vector2<MachineSpace>(dx: 0, dy: -0.75),
              feedMMPerMinute: 40
            )))
    )
  }

  @Test("explicit distance and feed remain a typed jog request")
  func explicitTypedJog() throws {
    let defaults = try sessionDefaults()
    let expected = RelativeJogRequest(
      delta: try Vector2<MachineSpace>(dx: 0, dy: 0.5),
      feedMMPerMinute: 60
    )

    #expect(
      parser.parse("jog y positive 0.5 millimeters at 60", defaults: defaults)
        == .intent(.relativeJog(expected))
    )
  }

  @Test("invalid and ambiguous numeric phrases cannot produce motion")
  func invalidNumericPhrases() throws {
    let defaults = try sessionDefaults()

    #expect(
      parser.parse("move x plus nan", defaults: defaults)
        == .rejected(.invalidDistance("nan")))
    #expect(
      parser.parse("move x plus -2", defaults: defaults)
        == .rejected(.invalidDistance("-2")))
    #expect(
      parser.parse("move x plus 2 at infinity", defaults: defaults)
        == .rejected(.invalidFeed("infinity")))
    #expect(
      parser.parse("move x plus 2 3", defaults: defaults)
        == .rejected(.invalidJogSyntax))
    #expect(
      parser.parse("move x plus 1,5", defaults: defaults)
        == .rejected(.multipleCommandsNotAllowed))
  }

  @Test("multi-command utterances are rejected rather than partially executed")
  func multipleCommands() throws {
    let defaults = try sessionDefaults()

    #expect(
      parser.parse("stop and x plus", defaults: defaults)
        == .rejected(.multipleCommandsNotAllowed))
    #expect(
      parser.parse("x plus then y minus", defaults: defaults)
        == .rejected(.multipleCommandsNotAllowed))
  }

  @Test("voice exposes pen up but never pen down")
  func penSurfaceIsOneWay() throws {
    let defaults = try sessionDefaults()

    #expect(parser.parse("pen up", defaults: defaults) == .intent(.raisePen))
    #expect(parser.parse("raise the pen", defaults: defaults) == .intent(.raisePen))
    #expect(
      parser.parse("pen down", defaults: defaults)
        == .rejected(.penDownNotAvailable))
    #expect(
      parser.parse("lower the pen", defaults: defaults)
        == .rejected(.penDownNotAvailable))
  }

  @Test("exact stop and cancel jog are the only priority intents")
  func stopPriority() throws {
    let defaults = try sessionDefaults()
    let stop = parser.parse("STOP!", defaults: defaults)
    let cancel = parser.parse("cancel jog", defaults: defaults)
    let jog = parser.parse("x plus", defaults: defaults)

    #expect(stop.priorityIntent == .cancelCurrentMotion)
    #expect(cancel.priorityIntent == .cancelCurrentMotion)
    #expect(jog.priorityIntent == nil)
    #expect(
      parser.parse("stop now", defaults: defaults)
        == .rejected(.unrecognizedCommand))
  }

  @Test("priority parsing does not depend on numeric session defaults")
  func defaultsFreePriorityParsing() {
    #expect(OperatorVoiceCommandParser.parsePriority("STOP!") == .cancelCurrentMotion)
    #expect(OperatorVoiceCommandParser.parsePriority("cancel jog") == .cancelCurrentMotion)
    #expect(OperatorVoiceCommandParser.parsePriority("stop and x plus") == nil)
    #expect(OperatorVoiceCommandParser.parsePriority("x plus") == nil)
  }

  @Test("status is closed and unknown speech is actionable")
  func statusAndUnknown() throws {
    let defaults = try sessionDefaults()

    #expect(parser.parse("controller status", defaults: defaults) == .intent(.requestStatus))
    let result = parser.parse("please do the thing", defaults: defaults)
    #expect(result == .rejected(.unrecognizedCommand))
    if case .rejected(let reason) = result {
      #expect(!reason.actionableDescription.isEmpty)
    }
  }

  @Test("invalid defaults cannot enter a voice session")
  func invalidDefaults() {
    #expect(throws: OperatorVoiceSessionDefaultsError.invalidXStep) {
      try OperatorVoiceSessionDefaults(xStepMM: 0, yStepMM: 1, feedMMPerMinute: 40)
    }
    #expect(throws: OperatorVoiceSessionDefaultsError.invalidYStep) {
      try OperatorVoiceSessionDefaults(xStepMM: 1, yStepMM: .infinity, feedMMPerMinute: 40)
    }
    #expect(throws: OperatorVoiceSessionDefaultsError.invalidFeed) {
      try OperatorVoiceSessionDefaults(xStepMM: 1, yStepMM: 1, feedMMPerMinute: .nan)
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

  @Test("speech output is injectable without a native audio dependency")
  func injectableSpeechOutput() async {
    let output = RecordingVoiceSpeechOutput()
    await output.speak("Controller idle")
    await output.stopSpeaking()

    #expect(await output.messages == ["Controller idle"])
    #expect(await output.stopCount == 1)
  }

  @Test("spoken feedback cannot be re-heard as a machine intent")
  func spokenFeedbackIsCommandFree() throws {
    let rejectionSamples: [OperatorVoiceParseRejection] = [
      .multipleCommandsNotAllowed,
      .invalidJogSyntax,
      .invalidDistance("bad"),
      .invalidFeed("bad"),
      .penDownNotAvailable,
      .unrecognizedCommand,
    ]
    let spokenSamples = rejectionSamples.map(OperatorVoiceSpokenFeedbackPolicy.rejection) + [
      OperatorVoiceSpokenFeedbackPolicy.invalidSessionDefaults,
      OperatorVoiceSpokenFeedbackPolicy.operationAlreadyInFlight,
    ]
    let acceptedPhraseFragments = [
      "x plus", "x minus", "y plus", "y minus", "pen up", "raise pen", "stop",
      "cancel jog",
    ]
    let defaults = try sessionDefaults()

    for spoken in spokenSamples {
      let lowercase = spoken.lowercased()
      for fragment in acceptedPhraseFragments {
        #expect(!lowercase.contains(fragment))
      }
      #expect(OperatorVoiceCommandParser.parsePriority(spoken) == nil)
      #expect(parser.parse(spoken, defaults: defaults).acceptedIntent == nil)
    }

    // The policy changes only what the application says; it never pauses the
    // input path or removes the defaults-free priority command.
    #expect(OperatorVoiceCommandParser.parsePriority("stop") == .cancelCurrentMotion)
  }

  private func sessionDefaults() throws -> OperatorVoiceSessionDefaults {
    try OperatorVoiceSessionDefaults(xStepMM: 1, yStepMM: 2, feedMMPerMinute: 40)
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
