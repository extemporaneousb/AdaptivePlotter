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

  var phrases: [String] {
    commands.map(\.title) + [
      "yes", "no", "it does", "it doesn't", "move", "go ahead", "move towards Y plus",
      "move towards Y minus", "move towards X plus", "move towards X minus",
      "stop", "stop moving", "that's enough", "repeat the question"
    ]
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
    let text = Self.normalized(transcript)
    if let stop = matchingStop(transcript) { return stop }
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
    let polite = Self.removingPolitePrefix(text)
    let words = Set(polite.split(separator: " ").map(String.init))
    let asksToMove = ["move", "go", "start", "continue", "keep moving"].contains {
      polite == $0 || polite.hasPrefix($0 + " ")
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
    let matches = commands.filter { Self.normalized($0.title) == polite }
    return matches.count == 1 ? matches[0] : nil
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
    if choicesChanged { restart() }
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
    let shouldSpeak = lastSpokenPrompt != context.prompt && !context.stopIsOnlyResponse
    lastSpokenPrompt = context.prompt
    activityTask = Task { [weak self, speech] in
      guard let self, self.generation == id, !Task.isCancelled else { return }
      await speech.prioritizeOperatorInput(context.stopIsOnlyResponse)
      if let priorPrompt { await speech.cancel(priorPrompt) }
      guard self.generation == id, !Task.isCancelled else { return }
      if shouldSpeak, !context.prompt.isEmpty {
        let request = PlotterSpeechEffectRequest(message: context.prompt)
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
          case .failed(let detail):
            self.stopInput()
            self.status = "\(detail) · Reconnecting microphone…"
            self.retryInput(context, generation: id)
          case .transcript(let text, let isFinal):
            // Endpoint on a settled partial as well as the recognizer's final:
            // Apple's live recognizer need not end a request after each reply.
            let changed = self.transcript != text
            self.transcript = text
            if isFinal || self.context?.matchingStop(text) != nil {
              self.finishUtterance(text, context: context, generation: id)
            } else if changed {
              self.silenceTask?.cancel()
              self.silenceTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                self?.finishUtterance(text, context: context, generation: id)
              }
            }
          }
        }
        if self.generation == id, !Task.isCancelled, self.isListening {
          self.stopInput()
          self.retryInput(context, generation: id)
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
    stopInput()
    let normalized = WorkbenchVoiceContext.normalized(text)
    if ["repeat", "repeat the question", "say that again"].contains(normalized) {
      repeatPrompt()
      return
    }
    guard let command = context.matching(text),
      let request = context.projection.request(for: command.id)
    else {
      status = "Heard “\(text)”. Try a short answer, move, stop, or repeat."
      // Keep the same question open, using the existing speech lane to avoid
      // feeding the recovery prompt back into recognition.
      let request = PlotterSpeechEffectRequest(
        message: "Please say " + context.commands.map(\.title).joined(separator: ", or ")
      )
      if context.stopIsOnlyResponse {
        // Keep listening rather than reading a Stop instruction into the mic.
        beginListening(context, generation: id)
        return
      }
      promptID = request.id
      Task { [weak self, speech] in
        guard self?.generation == id, self?.isEnabled == true else { return }
        _ = await speech.start(request)
        if self?.generation != id || self?.isEnabled != true { await speech.cancel(request.id) }
      }
      return
    }
    isSubmitting = true
    status = "Heard “\(text)” · \(command.title)"
    Task { [weak self, submit] in
      let disposition = await submit(request)
      guard let self, self.generation == id else { return }
      self.isSubmitting = false
      switch disposition {
      case .accepted:
        self.status = "\(command.title) accepted"
      case .refused(let refusal):
        self.status = refusal.remedy
      }
      // A normal state transition supplies a new context. A non-advancing
      // answer can keep this question current and must remain conversational.
      if !self.playbackIsActive { self.beginListening(context, generation: id) }
    }
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
