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

  init(presentation: OperatorActionPresentation, projection: PlotterUIProjection) {
    prompt = presentation.question?.prompt.accessibilityText
      ?? presentation.instructions.accessibilityText
    let requests = Set(presentation.actionStrip?.actions.map(\.request) ?? [])
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

  var phrases: [String] { commands.map(\.title) + ["yes", "no", "stop", "repeat the question"] }

  func matching(_ transcript: String) -> PlotterUIAction? {
    let text = Self.normalized(transcript)
    let exact = commands.filter { Self.normalized($0.title) == text }
    if exact.count == 1 { return exact[0] }
    let tokens = Set(text.split(separator: " ").map(String.init))
    let first = text.split(separator: " ").first.map(String.init) ?? ""
    let positive = ["yes", "yep", "yeah", "correct", "okay", "ok"].contains(first)
      || ["that s correct", "looks good", "it is"].contains(text)
    let hasNegation = !tokens.isDisjoint(with: ["no", "nope", "nah", "not"])
      || ["don t", "isn t", "can t", "didn t"].contains { text.contains($0) }
    let negative = ["no", "nope", "nah"].contains(first)
      || ["it isn t", "not yet", "that s not right"].contains(text)
    if positive && hasNegation { return nil }
    if positive != negative {
      let choices = commands.filter {
        guard case .learningAction(let request) = $0.intent,
          case .choice(let choice) = request.action else { return false }
        return choice == (negative ? .no : .yes)
      }
      if choices.count == 1 { return choices[0] }
    }
    if ["stop", "stop now", "please stop"].contains(text) {
      let stops = commands.filter {
        guard case .learningAction(let request) = $0.intent else { return false }
        switch request.action {
        case .stop, .stopPenInteraction, .boundary(.stop): return true
        default: return false
        }
      }
      if stops.count == 1 { return stops[0] }
    }
    let polite = text.hasPrefix("please ") ? String(text.dropFirst(7)) : text
    let matches = commands.filter { Self.normalized($0.title) == polite }
    return matches.count == 1 ? matches[0] : nil
  }

  static func normalized(_ text: String) -> String {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
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
    self.context = context
    restart()
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
      if let priorPrompt { Task { await speech.cancel(priorPrompt) } }
      status = isEnabled ? "Waiting for current exercise choices" : "Voice off"
      return
    }
    status = "Preparing Voice…"
    let shouldSpeak = lastSpokenPrompt != context.prompt
    lastSpokenPrompt = context.prompt
    activityTask = Task { [weak self, speech] in
      if let priorPrompt { await speech.cancel(priorPrompt) }
      guard let self, self.generation == id, !Task.isCancelled else { return }
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
          self.beginListening(context, generation: id)
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
            self.status = "\(detail) · Retry Voice"
          case .transcript(let text, let isFinal):
            // Endpoint on a settled partial as well as the recognizer's final:
            // Apple's live recognizer need not end a request after each reply.
            let changed = self.transcript != text
            self.transcript = text
            if isFinal {
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
      } catch is CancellationError {
      } catch {
        guard self.generation == id, !Task.isCancelled else { return }
        self.stopInput()
        self.status = error.localizedDescription
      }
    }
  }

  private func finishUtterance(_ text: String, context: WorkbenchVoiceContext, generation id: UUID) {
    guard generation == id, isEnabled, isListening, !playbackIsActive else { return }
    stopInput()
    let normalized = WorkbenchVoiceContext.normalized(text)
    if ["repeat", "repeat the question", "say that again"].contains(normalized) {
      repeatPrompt()
      return
    }
    guard let command = context.matching(text),
      let request = context.projection.request(for: command.id)
    else {
      status = "Heard “\(text)”. Say a button label, or repeat."
      // Keep the same question open, using the existing speech lane to avoid
      // feeding the recovery prompt back into recognition.
      let request = PlotterSpeechEffectRequest(
        message: "Please say " + context.commands.map(\.title).joined(separator: ", or ")
      )
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
