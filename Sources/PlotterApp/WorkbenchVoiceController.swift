import Foundation
import Observation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI

/// A copy of the current rendered choices, never a second action compiler.
struct WorkbenchVoiceContext: Equatable {
  let prompt: String
  let commands: [PlotterUIAction]
  let projection: PlotterUIProjection

  init(
    presentation: OperatorActionPresentation, projection: PlotterUIProjection,
    actionStrip: PlotterUILearningActionStripDecision? = nil
  ) {
    prompt = presentation.question?.prompt.accessibilityText
      ?? presentation.instructions.accessibilityText
    let requests = Set((actionStrip ?? presentation.actionStrip)?.actions.map(\.request) ?? [])
    commands = projection.actions.filter { action in
      guard action.isAvailable, case .learningAction(let request) = action.intent else { return false }
      return requests.contains(request)
    }
    self.projection = projection
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prompt == rhs.prompt && lhs.commands == rhs.commands
      && lhs.projection.revision == rhs.projection.revision
      && lhs.projection.runtimeRevisions == rhs.projection.runtimeRevisions
  }

  var stopIsOnlyResponse: Bool {
    !commands.isEmpty && commands.allSatisfy(\.isLearningStop)
  }

  var conversationChoices: [String] {
    commands.map { $0.isLearningStop ? "stop" : $0.id.rawValue }
  }

  /// Short replies are aliases for unique, currently offered typed actions.
  /// A negative observation remains No; it must never become cancellation.
  private func reply(for action: PlotterUIAction) -> String {
    guard case .learningAction(let request) = action.intent else { return action.title }
    switch request.action {
    case .stop, .stopPenInteraction, .boundary(.stop): return "Stop"
    case .choice(.yes), .cameraCalibration(.acceptProposal), .tipCalibration(.acceptProposal),
      .borderValidation(.acceptObservedPrediction): return "Confirmed"
    case .choice(.no): return "No"
    case .cancel, .boundary(.cancel): return "Cancel"
    case .cameraCalibration(.rejectProposal), .tipCalibration(.rejectProposal),
      .borderValidation(.reject): return "Reject"
    case .start, .boundary(.acquire), .boundary(.moveToEstimatedCenter),
      .cameraCalibration(.buildFivePositionProposal), .tipCalibration(.beginFourMarkBatch),
      .tipCalibration(.revalidateCheckpoint): return "Start"
    default: return action.title
    }
  }

  var replies: [String] {
    commands.compactMap { command in
      let short = reply(for: command)
      let candidate = commands.filter { reply(for: $0) == short }.count == 1 ? short : command.title
      return matching(candidate)?.id == command.id ? candidate : nil
    }
  }

  var responseHint: String {
    replies.isEmpty ? "Use the buttons for these choices."
      : "Say " + replies.joined(separator: " or ") + "."
  }

  var spokenPrompt: String {
    if let movement = commands.first(where: { $0.startsBoundaryMotion }) {
      return movement.title.replacingOccurrences(of: "Y+", with: "positive Y")
        .replacingOccurrences(of: "Y−", with: "negative Y")
        .replacingOccurrences(of: "X+", with: "positive X")
        .replacingOccurrences(of: "X−", with: "negative X") + "? " + responseHint
    }
    return prompt + " " + responseHint
  }

  var phrases: [String] {
    // Keep Stop in the recognizer vocabulary before movement starts, too.
    ["Stop", "Confirmed", "Cancel", "Start"] + replies + ["yes", "no", "repeat"]
  }

  func matchingStop(_ transcript: String) -> PlotterUIAction? {
    let text = Self.removingPolitePrefix(Self.normalized(transcript))
    let first = text.split(separator: " ").first
    // An explicit Stop takes effect before any following explanation. Negation
    // before the command ("please don't stop") still is not a Stop request.
    guard first == "stop" || first == "halt"
      || text == "that s enough" || text == "enough"
    else { return nil }
    return uniqueCommand { action in
      switch action {
      case .stop, .stopPenInteraction, .boundary(.stop): true
      default: false
      }
    }
  }

  private func uniqueCommand(_ matches: (PlotterLearningAction) -> Bool) -> PlotterUIAction? {
    let candidates = commands.filter {
      guard case .learningAction(let request) = $0.intent else { return false }
      return matches(request.action)
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func hasNegation(_ text: String) -> Bool {
    let tokens = Set(text.split(separator: " ").map(String.init))
    return !tokens.isDisjoint(with: ["no", "nope", "nah", "not", "never"])
      || ["don t", "doesn t", "isn t", "aren t", "can t", "didn t", "won t"]
        .contains { text.contains($0) }
  }

  func matching(_ transcript: String) -> PlotterUIAction? {
    let text = Self.removingPolitePrefix(Self.normalized(transcript))
    if let stop = matchingStop(transcript) { return stop }
    let alias = commands.filter { Self.normalized(reply(for: $0)) == text }
    if alias.count > 1 { return nil }
    if alias.count == 1 { return alias[0] }
    let exact = commands.filter { Self.normalized($0.title) == text }
    if exact.count == 1 { return exact[0] }
    let first = text.split(separator: " ").first.map(String.init) ?? ""
    let positive = ["yes", "yep", "yeah", "correct", "okay", "ok"].contains(first)
      || ["that s correct", "looks good", "it is", "it does", "that s right", "it did"].contains(text)
    let hasNegation = Self.hasNegation(text)
    let negative = ["no", "nope", "nah"].contains(first)
      || ["it isn t", "it doesn t", "it does not", "it didn t", "it did not",
          "not yet", "that s not right", "that s wrong", "no it doesn t"]
        .contains { text == $0 || text.hasPrefix($0 + " ") }
    if positive && hasNegation { return nil }
    if positive != negative {
      let choices = commands.filter {
        guard case .learningAction(let request) = $0.intent,
          case .choice(let choice) = request.action else { return false }
        return choice == (negative ? .no : .yes)
      }
      if choices.count == 1 { return choices[0] }
    }
    let words = Set(text.split(separator: " ").map(String.init))
    let asksToMove = ["move", "go", "start", "continue", "keep moving"].contains {
      text == $0 || text.hasPrefix($0 + " ")
    }
    if asksToMove && !hasNegation {
      // The offered Boundary action supplies the direction. Explicit axis/sign
      // words qualify it; they never choose a different, unoffered movement.
      let x = !words.isDisjoint(with: ["x", "ex", "axe"])
      let y = !words.isDisjoint(with: ["y", "why"])
      let plus = !words.isDisjoint(with: ["plus", "positive"])
      let minus = !words.isDisjoint(with: ["minus", "negative"])
      if let movement = uniqueCommand({ action in
        guard case .boundary(.acquire(let direction, _)) = action else { return false }
        let isX = direction == .negativeX || direction == .positiveX
        let isPlus = direction == .positiveX || direction == .positiveY
        return (!x || isX) && (!y || !isX) && (!plus || isPlus) && (!minus || !isPlus)
      }) { return movement }
    }
    return nil
  }

  private static func removingPolitePrefix(_ text: String) -> String {
    for prefix in ["could you please ", "can you please ", "would you ", "could you ", "can you ", "please "] {
      if text.hasPrefix(prefix) { return String(text.dropFirst(prefix.count)) }
    }
    return text
  }

  static func normalized(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "+", with: " plus ")
      .replacingOccurrences(of: "−", with: " minus ")
      .replacingOccurrences(of: "-", with: " minus ")
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }.joined(separator: " ")
  }
}

private extension PlotterUIAction {
  var startsBoundaryMotion: Bool {
    guard case .learningAction(let request) = intent else { return false }
    switch request.action {
    case .boundary(.acquire), .boundary(.moveToEstimatedCenter): return true
    default: return false
    }
  }
}

/// Window-local speech interaction. Recognition and meter changes stay outside
/// the semantic observation graph. All accepted input uses the existing sink.
@MainActor @Observable
final class WorkbenchVoiceController {
  private(set) var isEnabled = false
  private(set) var isListening = false
  private(set) var status = "Voice off"
  private(set) var transcript = ""
  private(set) var inputLevel: Float = 0
  @ObservationIgnored private let speech: PlotterSpeechEffectRuntime
  @ObservationIgnored private let listener: any SpeechListening
  @ObservationIgnored private let submit: (PlotterUIRequest) async -> PlotterUIRequestDisposition
  @ObservationIgnored private var context: WorkbenchVoiceContext?
  @ObservationIgnored private var activityTask: Task<Void, Never>?
  @ObservationIgnored private var inputTask: Task<Void, Never>?
  @ObservationIgnored private var silenceTask: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var promptID: UUID?
  @ObservationIgnored private var lastSpokenPrompt: String?
  @ObservationIgnored private var isSubmitting = false
  @ObservationIgnored private var playbackIsActive = false
  @ObservationIgnored private var submissionID: UUID?
  @ObservationIgnored private var submittingStop = false
  @ObservationIgnored private var preservingInputForStop = false
  @ObservationIgnored private var consumedPrefix = ""
  @ObservationIgnored private var lastTranscriptChange: ContinuousClock.Instant?

  init(
    speech: PlotterSpeechEffectRuntime,
    listener: (any SpeechListening)? = nil,
    submit: @escaping (PlotterUIRequest) async -> PlotterUIRequestDisposition
  ) {
    self.speech = speech
    self.listener = listener ?? NativeSpeechListener()
    self.submit = submit
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    lastSpokenPrompt = nil
    restart()
  }

  func update(_ context: WorkbenchVoiceContext?) {
    guard self.context != context else { return }
    let choicesChanged = self.context?.conversationChoices != context?.conversationChoices
      || (self.context?.prompt != context?.prompt && context?.stopIsOnlyResponse != true)
    self.context = context
    // Controller telemetry can refresh the request revision without changing
    // the question. Keep the microphone open and submit with the newest copy.
    if choicesChanged {
      if preservingInputForStop, isListening, context?.stopIsOnlyResponse == true {
        // The same recognition request spans the operator's Start and Stop.
        // Only Stop can consume its remaining transcript in the new context.
        silenceTask?.cancel()
        silenceTask = nil
        lastSpokenPrompt = context?.spokenPrompt
        let id = generation
        Task { [weak self, speech] in
          guard self?.generation == id else { return }
          await speech.prioritizeOperatorInput(true)
        }
      } else {
        restart()
      }
    }
  }

  func repeatPrompt() {
    lastSpokenPrompt = nil
    restart()
  }

  func stop() {
    setEnabled(false)
  }

  private func restart() {
    generation = UUID()
    let id = generation
    activityTask?.cancel()
    stopInput()
    isSubmitting = false
    submissionID = nil
    submittingStop = false
    preservingInputForStop = false
    consumedPrefix = ""
    let priorPrompt = promptID
    promptID = nil
    guard isEnabled, let context, !context.commands.isEmpty else {
      Task { [weak self, speech] in
        guard self?.generation == id else { return }
        await speech.prioritizeOperatorInput(false)
        if let priorPrompt { await speech.cancel(priorPrompt) }
      }
      status = isEnabled ? "Waiting for current exercise choices" : "Voice off"
      return
    }
    status = "Preparing Voice…"
    let shouldSpeak = lastSpokenPrompt != context.spokenPrompt && !context.stopIsOnlyResponse
    lastSpokenPrompt = context.spokenPrompt
    activityTask = Task { [weak self, speech] in
      guard let self, self.generation == id, !Task.isCancelled else { return }
      await speech.prioritizeOperatorInput(context.stopIsOnlyResponse)
      if let priorPrompt { await speech.cancel(priorPrompt) }
      guard self.generation == id, !Task.isCancelled else { return }
      if shouldSpeak {
        let request = PlotterSpeechEffectRequest(message: context.spokenPrompt)
        self.promptID = request.id
        _ = await speech.start(request)
        guard self.generation == id, !Task.isCancelled else {
          await speech.cancel(request.id)
          return
        }
      }
      let activity = await speech.activity()
      for await speaking in activity {
        guard self.generation == id, !Task.isCancelled else { return }
        self.playbackIsActive = speaking
        if speaking {
          self.stopInput()
          self.status = "Speaking…"
        } else if !self.isSubmitting {
          if self.inputTask == nil { self.beginListening(self.context ?? context, generation: id) }
        }
      }
      if self.generation == id { self.stop() }
    }
  }

  private func beginListening(_ context: WorkbenchVoiceContext, generation id: UUID) {
    stopInput()
    transcript = ""
    consumedPrefix = ""
    lastTranscriptChange = nil
    status = "Opening microphone…"
    inputTask = Task { [weak self] in
      guard let self else { return }
      do {
        let events = try await self.listener.start(contextualPhrases: context.phrases)
        guard self.generation == id, !Task.isCancelled else { return }
        self.isListening = true
        self.status = "Listening · system microphone"
        for await event in events {
          guard self.generation == id, !Task.isCancelled, self.isListening else { return }
          switch event {
          case .level(let value): self.inputLevel = value
          case .ended:
            if !self.submittingStop {
              self.beginListening(self.context ?? context, generation: id)
            }
          case .failed(let detail):
            if self.submittingStop { continue }
            self.stopInput()
            self.status = "\(detail) · Reconnecting microphone…"
            self.retryInput(context, generation: id)
          case .transcript(let text, let isFinal, let observedAt):
            // Endpoint on a settled partial as well as the recognizer's final:
            // Apple's live recognizer need not end a request after each reply.
            let changed = self.transcript != text
            if changed, self.context?.stopIsOnlyResponse == true, !self.submittingStop,
              let previous = self.lastTranscriptChange,
              observedAt - previous >= .milliseconds(900)
            {
              // Segment by recognition time, even if both callbacks queue
              // behind a busy UI thread. No timer or microphone restart gates Stop.
              self.consumedPrefix = WorkbenchVoiceContext.normalized(self.transcript)
            }
            if changed { self.lastTranscriptChange = observedAt }
            self.transcript = text
            let reply = self.unconsumedReply(text)
            if self.context?.matchingStop(reply) != nil {
              self.finishUtterance(reply, context: context, generation: id)
            } else if self.isSubmitting || self.context?.stopIsOnlyResponse == true {
              continue
            } else if isFinal {
              self.finishUtterance(reply, context: context, generation: id)
            } else if changed {
              self.silenceTask?.cancel()
              self.silenceTask = Task { [weak self] in
                let shortReply = self?.context?.replies.contains {
                  WorkbenchVoiceContext.normalized($0) == WorkbenchVoiceContext.normalized(reply)
                } == true
                do { try await Task.sleep(for: .milliseconds(shortReply ? 350 : 900)) } catch { return }
                self?.finishUtterance(reply, context: context, generation: id)
              }
            }
          }
        }
        if self.generation == id, !Task.isCancelled, self.isListening, !self.submittingStop {
          self.beginListening(self.context ?? context, generation: id)
        }
      } catch is CancellationError {
      } catch {
        guard self.generation == id, !Task.isCancelled else { return }
        self.stopInput()
        self.status = error.localizedDescription
      }
    }
  }

  private func retryInput(_ context: WorkbenchVoiceContext, generation id: UUID) {
    silenceTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
      guard let self, self.generation == id, self.isEnabled, !self.playbackIsActive else { return }
      self.beginListening(self.context ?? context, generation: id)
    }
  }

  private func finishUtterance(_ text: String, context: WorkbenchVoiceContext, generation id: UUID) {
    guard generation == id, isEnabled, isListening, !playbackIsActive else { return }
    let context = self.context ?? context
    let stop = context.matchingStop(text)
    guard !isSubmitting || (stop != nil && !submittingStop) else { return }
    let normalized = WorkbenchVoiceContext.normalized(text)
    if ["repeat", "repeat the question", "say that again"].contains(normalized) {
      repeatPrompt()
      return
    }
    guard let command = context.matching(text),
      let request = context.projection.request(for: command.id)
    else {
      if context.stopIsOnlyResponse { return }
      stopInput()
      status = "Heard “\(text)”. " + context.responseHint
      // Keep the same question open, using the existing speech lane to avoid
      // feeding the recovery prompt back into recognition.
      let request = PlotterSpeechEffectRequest(
        message: context.responseHint
      )
      promptID = request.id
      Task { [weak self, speech] in
        guard self?.generation == id, self?.isEnabled == true else { return }
        _ = await speech.start(request)
        if self?.generation != id || self?.isEnabled != true { await speech.cancel(request.id) }
      }
      return
    }
    silenceTask?.cancel()
    silenceTask = nil
    isSubmitting = true
    submittingStop = stop != nil
    preservingInputForStop = command.startsBoundaryMotion
    consumedPrefix = WorkbenchVoiceContext.normalized(transcript)
    let submission = UUID()
    submissionID = submission
    // Do not put synchronous AVAudioEngine teardown ahead of the Stop sink.
    // Keep input through Boundary Start as well, so Stop can interrupt admission.
    if stop == nil && !preservingInputForStop { stopInput() }
    status = "Heard “\(text)” · \(command.title)"
    Task(priority: stop == nil ? nil : .userInitiated) { [weak self, submit, speech] in
      guard let self, self.generation == id, self.submissionID == submission else { return }
      if command.startsBoundaryMotion {
        // Suppress the movement cue before the owner can issue it. Otherwise
        // playback can close the microphone before the Stop projection arrives.
        await speech.prioritizeOperatorInput(true)
        guard self.generation == id, self.submissionID == submission else { return }
      }
      let disposition = await submit(request)
      guard self.generation == id, self.submissionID == submission else { return }
      self.isSubmitting = false
      self.submittingStop = false
      switch disposition {
      case .accepted:
        self.status = "\(command.title) accepted"
      case .refused(let refusal):
        self.status = refusal.remedy
        self.preservingInputForStop = false
        await speech.prioritizeOperatorInput(self.context?.stopIsOnlyResponse == true)
        guard self.generation == id, self.submissionID == submission else { return }
      }
      // A normal state transition supplies a new context. A non-advancing
      // answer can keep this question current and must remain conversational.
      if !self.playbackIsActive, !self.preservingInputForStop {
        self.beginListening(self.context ?? context, generation: id)
      }
    }
  }

  private func unconsumedReply(_ text: String) -> String {
    let normalized = WorkbenchVoiceContext.normalized(text)
    guard !consumedPrefix.isEmpty else { return text }
    if normalized == consumedPrefix { return "" }
    if normalized.hasPrefix(consumedPrefix + " ") {
      return String(normalized.dropFirst(consumedPrefix.count + 1))
    }
    return text
  }

  private func stopInput() {
    inputTask?.cancel()
    inputTask = nil
    silenceTask?.cancel()
    silenceTask = nil
    listener.stop()
    isListening = false
    inputLevel = 0
  }
}
