import PlotterRuntime
import SwiftUI

/// App-local labels for the runtime-owned preflight definitions.
///
/// `PlotterRuntime` owns sequence semantics, progress, evidence, and readiness.
/// This type only turns those typed values into compact operator-facing text.
enum PreflightCalibrationPresentation {
  static let title = "Motion Preflight"
  static let subtitle = "Calibrate Plotter · voice, controller, and live-camera evidence"

  static func title(for id: PreflightSequenceID) -> String {
    switch id {
    case .boundaryNegativeX: "X− Boundary"
    case .boundaryPositiveX: "X+ Boundary"
    case .boundaryNegativeY: "Y− Boundary"
    case .boundaryPositiveY: "Y+ Boundary"
    case .penUpConfirmation: "Pen Up"
    case .penDownConfirmation: "Pen Down"
    }
  }

  static func shortLabel(for id: PreflightSequenceID) -> String {
    switch id {
    case .boundaryNegativeX: "X−"
    case .boundaryPositiveX: "X+"
    case .boundaryNegativeY: "Y−"
    case .boundaryPositiveY: "Y+"
    case .penUpConfirmation: "UP"
    case .penDownConfirmation: "DOWN"
    }
  }

  static func requiredVoicePhrase(for definition: PreflightSequenceDefinition) -> String {
    definition.voiceResponses.map(\.exactPhrase).joined(separator: " → ")
  }

  static func expectedEvidenceOutput(for definition: PreflightSequenceDefinition) -> String {
    switch definition.sequenceClass {
    case .boundaryMeasurement:
      "Final controller MPos, exact live frame, measured boundary, and a posterior adjustment to the estimated drawing frame."
    case .penPositionConfirmation:
      "Settled controller pen command, the operator's explicit physical pen-state confirmation, and a paired exact live-camera frame. The frame is observation, not pen-height proof."
    }
  }

  static func phaseLabel(for transaction: PreflightTransaction?) -> String {
    guard let transaction else { return "NOT STARTED" }
    return switch transaction.state {
    case .notStarted: "NOT STARTED"
    case .active: "CURRENT"
    case .cancelling: "STOPPING SPEECH"
    case .succeeded: "COMPLETE"
    case .failed: "NEEDS ATTENTION"
    case .cancelled: "CANCELLED"
    }
  }

  static func phaseLabel(for rehearsal: PreflightRehearsal?) -> String {
    guard let rehearsal else { return "NOT REHEARSED" }
    return switch rehearsal.state {
    case .notStarted: "NOT REHEARSED"
    case .running: "REHEARSING"
    case .completed: "REHEARSED"
    case .cancelled: "CANCELLED"
    }
  }

  static func actionDescription(_ action: PreflightAction) -> String {
    switch action {
    case .startSpeechListening:
      "Start speech listening for this sequence."
    case .stopSpeechListening:
      "Stop speech listening for this sequence."
    case .speakPrompt(let prompt):
      "Speak: “\(prompt)”"
    case .awaitVoice(let response):
      "Say \(response.exactPhrase)."
    case .startBoundaryJog(let direction):
      "Move slowly toward the \(direction.displayName) end stop."
    case .cancelBoundaryJogAndAwaitIdle(let direction):
      "Cancel the \(direction.displayName) jog and wait for Idle."
    case .captureFreshCameraFrame:
      "Capture the newest exact live-camera frame."
    case .measureBoundary(let direction):
      "Measure the visible \(direction.displayName) field edge."
    case .adjustDrawingFramePosterior(let direction):
      "Constrain the nearest estimated drawing-frame edge using the \(direction.displayName) final MPos and exact-frame tool centroid."
    case .actuatePen(let command):
      "Command Pen \(command.commandedState == .up ? "Up" : "Down") and wait for settle."
    case .awaitPhysicalPenConfirmation(let state, let response):
      "Observe the mechanism and say \(response.exactPhrase) to confirm pen \(state.rawValue)."
    }
  }

  static func eventDescription(_ expectation: PreflightEventExpectation) -> String {
    switch expectation {
    case .speechListeningStarted:
      "Speech listening is active for this sequence."
    case .speechListeningStopped:
      "Speech listening is stopped."
    case .promptSpoken:
      "The spoken prompt finishes."
    case .exactVoiceResponse(let response):
      "Exact \(response.exactPhrase) is accepted in this sequence."
    case .boundaryJogStarted(let direction):
      "The closed \(direction.displayName) boundary jog is active."
    case .boundaryJogCancelled(let direction):
      "The \(direction.displayName) jog is cancelled at Idle with a final MPos."
    case .freshFrameCaptured:
      "A frame newer than the completed motion or spoken confirmation and its camera configuration are identified."
    case .boundaryMeasured(let direction):
      "A confidence-bearing \(direction.displayName) measurement is produced."
    case .drawingFramePosteriorAdjusted(let direction):
      "The \(direction.displayName) controller position and observed tool centroid update the drawing-frame posterior."
    case .penCommandSettled(let command):
      "The Pen \(command.commandedState == .up ? "Up" : "Down") command settles without ambiguity."
    case .physicalPenConfirmed(let state, let response):
      "Exact \(response.exactPhrase) records physical pen \(state.rawValue)."
    }
  }

  static func evidenceKindLabel(_ kind: PreflightEvidenceKind) -> String {
    switch kind {
    case .speechSystem: "SPEECH"
    case .operatorVoice: "VOICE"
    case .operatorObservation: "OPERATOR"
    case .controller: "CONTROLLER"
    case .camera: "CAMERA"
    case .visionMeasurement: "VISION"
    case .observedInk: "INK"
    }
  }
}

enum PreflightCalibrationMode: Equatable {
  case physical
  case simulatorRehearsal

  var subtitle: String {
    switch self {
    case .physical:
      PreflightCalibrationPresentation.subtitle
    case .simulatorRehearsal:
      "Simulator walkthrough · no microphone, controller, evidence, or readiness authority"
    }
  }
}

/// Compact, non-paged presentation for the zero-order motion preflight.
///
/// The host presents this from Learning and translates Start/Cancel into typed
/// runtime requests. Starting a sequence also starts listening; there is no
/// independent Speech mode in this surface. This view never interprets speech
/// or issues motion itself.
struct PreflightCalibrationView: View {
  @Binding var selectedSequenceID: PreflightSequenceID

  let catalog: [PreflightSequenceDefinition]
  let transactions: [PreflightSequenceID: PreflightTransaction]
  let rehearsals: [PreflightSequenceID: PreflightRehearsal]
  let readiness: PreflightTrainingReadiness
  let mode: PreflightCalibrationMode
  let startUnavailableReason: (PreflightSequenceID) -> String?
  let listeningStatus: String
  let errorText: String?
  let onStart: (PreflightSequenceID) -> Void
  let onCancel: (PreflightSequenceID) -> Void

  init(
    selectedSequenceID: Binding<PreflightSequenceID>,
    catalog: [PreflightSequenceDefinition] = PreflightSequenceCatalog.all,
    transactions: [PreflightSequenceID: PreflightTransaction],
    rehearsals: [PreflightSequenceID: PreflightRehearsal] = [:],
    readiness: PreflightTrainingReadiness,
    mode: PreflightCalibrationMode = .physical,
    startUnavailableReason: @escaping (PreflightSequenceID) -> String? = { _ in nil },
    listeningStatus: String = "Speech starts with a sequence.",
    errorText: String? = nil,
    onStart: @escaping (PreflightSequenceID) -> Void,
    onCancel: @escaping (PreflightSequenceID) -> Void
  ) {
    _selectedSequenceID = selectedSequenceID
    self.catalog = catalog
    self.transactions = transactions
    self.rehearsals = rehearsals
    self.readiness = readiness
    self.mode = mode
    self.startUnavailableReason = startUnavailableReason
    self.listeningStatus = listeningStatus
    self.errorText = errorText
    self.onStart = onStart
    self.onCancel = onCancel
  }

  private var selectedDefinition: PreflightSequenceDefinition {
    catalog.first(where: { $0.id == selectedSequenceID })
      ?? PreflightSequenceCatalog.definition(for: selectedSequenceID)
  }

  private var selectedTransaction: PreflightTransaction? {
    transactions[selectedDefinition.id]
  }

  private var selectedRehearsal: PreflightRehearsal? {
    rehearsals[selectedDefinition.id]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()

      HStack(alignment: .top, spacing: 0) {
        sequenceList
          .frame(minWidth: 190, idealWidth: 220, maxWidth: 245)

        Divider()

        sequenceDetail
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      Divider()
      controls
    }
    .frame(minWidth: 760, minHeight: 500)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(PreflightCalibrationPresentation.title)
            .font(.title2.weight(.semibold))
          Text(mode.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Label(
          headerStatusText,
          systemImage: mode == .simulatorRehearsal ? "play.rectangle.fill" : "checklist"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(headerStatusColor)
      }

      HStack(spacing: 10) {
        ProgressView(value: headerProgress)
        .frame(maxWidth: 260)

        Text(headerSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .background(.ultraThinMaterial)
  }

  private var headerStatusText: String {
    if mode == .simulatorRehearsal { return "Simulator Rehearsal" }
    return readiness.isReady ? "Ready to Train" : "Preflight Required"
  }

  private var headerStatusColor: Color {
    if mode == .simulatorRehearsal { return .blue }
    return readiness.isReady ? .green : .orange
  }

  private var headerProgress: Double {
    if mode == .simulatorRehearsal { return selectedRehearsal?.progress ?? 0 }
    return Double(readiness.successfulSequenceClasses.count)
      / Double(max(1, readiness.minimumSuccessfulSequenceClasses))
  }

  private var headerSummary: String {
    if mode == .simulatorRehearsal {
      guard let selectedRehearsal else {
        return "Choose a sequence and play its hypothetical participant/action/event flow"
      }
      return "\(selectedRehearsal.completedStepCount) of \(selectedDefinition.steps.count) scripted steps · no evidence recorded"
    }
    return readinessSummary
  }

  private var readinessSummary: String {
    if readiness.isReady {
      return "\(readiness.successfulSequenceIDs.count) sequences cover the required preflight classes"
    }
    let missing = readiness.missingRequiredClasses
      .map(\.displayName)
      .sorted()
      .joined(separator: ", ")
    if !missing.isEmpty {
      return "Need \(readiness.minimumSuccessfulSequenceClasses) sequence classes · missing: \(missing)"
    }
    if !readiness.hasSuccessfulPenUpConfirmation {
      return "Complete Pen Up confirmation before training"
    }
    return "Current pen state is \(readiness.currentPenState.rawValue) · Pen Up required"
  }

  private var sequenceList: some View {
    List(catalog, selection: $selectedSequenceID) { definition in
      HStack(spacing: 9) {
        Image(systemName: definition.sequenceClass == .boundaryMeasurement ? "move.3d" : "pencil.tip")
          .foregroundStyle(.secondary)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(PreflightCalibrationPresentation.title(for: definition.id))
          Text(phaseLabel(for: definition.id))
            .font(.caption)
            .foregroundStyle(phaseColor(for: definition.id))
        }
      }
      .tag(definition.id)
    }
    .listStyle(.sidebar)
  }

  private var sequenceDetail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text(PreflightCalibrationPresentation.title(for: selectedDefinition.id))
              .font(.title3.weight(.semibold))
            Text(selectedDefinition.summary)
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Text(phaseLabel(for: selectedDefinition.id))
            .font(.caption.weight(.semibold))
            .foregroundStyle(phaseColor(for: selectedDefinition.id))
        }

        if let progress = selectedProgress {
          HStack(spacing: 10) {
            ProgressView(value: progress)
            Text("\(selectedCompletedStepCount) / \(selectedDefinition.steps.count) steps")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if mode == .physical, case .failed(let reason) = selectedTransaction?.state {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
        }

        VStack(alignment: .leading, spacing: 5) {
          Text(mode == .simulatorRehearsal ? "SCRIPTED VOICE CUE" : "REQUIRED VOICE PHRASE")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(PreflightCalibrationPresentation.requiredVoicePhrase(for: selectedDefinition))
            .font(.body.weight(.semibold))
            .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 8) {
          Text("Participants, actions, and events")
            .font(.headline)
            .foregroundStyle(.secondary)

          ForEach(Array(selectedDefinition.steps.enumerated()), id: \.element.id) { index, step in
            timelineRow(step, ordinal: index + 1)
          }
        }

        evidenceOutput
      }
      .padding(14)
    }
  }

  private func timelineRow(_ step: PreflightStep, ordinal: Int) -> some View {
    let isCurrent = selectedCurrentStep?.id == step.id
    let isComplete = ordinal <= selectedCompletedStepCount

    return HStack(alignment: .top, spacing: 9) {
      Image(systemName: isComplete ? "checkmark" : "\(ordinal).circle.fill")
        .font(.caption.monospaced().bold())
        .foregroundStyle(isCurrent ? Color.white : isComplete ? Color.green : Color.secondary)
        .frame(width: 22, height: 22)
        .background(isCurrent ? Color.accentColor : Color.clear, in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(step.participant.displayName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
        Text(PreflightCalibrationPresentation.actionDescription(step.action))
          .font(.callout.weight(isCurrent ? .semibold : .regular))
        Label(
          PreflightCalibrationPresentation.eventDescription(step.expectedEvent),
          systemImage: "arrow.turn.down.right"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(8)
    .background(
      isCurrent ? Color.accentColor.opacity(0.1) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
  }

  private var evidenceOutput: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(mode == .simulatorRehearsal ? "Rehearsal output" : "Evidence and output")
        .font(.headline)
        .foregroundStyle(.secondary)
      if mode == .simulatorRehearsal {
        Label(
          "Playback highlights the expected steps only. It cannot create evidence, readiness, controller position, camera measurements, or a drawing-frame posterior.",
          systemImage: "play.rectangle"
        )
        .font(.callout)
        .foregroundStyle(.blue)
      } else {
        Text(PreflightCalibrationPresentation.expectedEvidenceOutput(for: selectedDefinition))
          .font(.callout)
      }
      Divider()

      if mode == .simulatorRehearsal {
        Text("No evidence is recorded during a simulator rehearsal.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else if let evidence = selectedTransaction?.evidenceSummaries, !evidence.isEmpty {
        ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(PreflightCalibrationPresentation.evidenceKindLabel(item.kind))
              .font(.caption2.monospaced().bold())
              .foregroundStyle(.secondary)
              .frame(width: 76, alignment: .leading)
            Text(item.summary)
              .font(.callout.monospaced())
              .textSelection(.enabled)
          }
        }
      } else {
        Text("No evidence recorded yet.")
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  private var controls: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Label(
          mode == .simulatorRehearsal
            ? "Simulator playback · microphone and controller remain off"
            : listeningStatus,
          systemImage: mode == .simulatorRehearsal ? "play.rectangle" : "mic.fill"
        )
          .font(.caption)
          .foregroundStyle(.secondary)

        if !selectedIsInFlight,
          let reason = startUnavailableReason(selectedDefinition.id)
        {
          Text("Start unavailable: \(reason)")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        } else {
          Text(
            mode == .simulatorRehearsal
              ? "Play advances the typed timeline without satisfying preflight."
              : "Start enables listening. Runtime checks retain controller authority."
          )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let errorText {
          Label(errorText, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }

      Spacer()

      Button(mode == .simulatorRehearsal ? "Stop Rehearsal" : "Cancel Sequence") {
        onCancel(selectedDefinition.id)
      }
      .disabled(!selectedIsActive)

      Button(primaryActionTitle) {
        onStart(selectedDefinition.id)
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        selectedIsInFlight
          || startUnavailableReason(selectedDefinition.id) != nil
      )
    }
    .padding(12)
    .background(.ultraThinMaterial)
  }

  private var primaryActionTitle: String {
    if mode == .simulatorRehearsal {
      return selectedRehearsal?.state == .completed ? "Play Again" : "Play Rehearsal"
    }
    return isSucceeded(selectedTransaction) ? "Run Again" : "Start Sequence"
  }

  private var selectedIsActive: Bool {
    if mode == .simulatorRehearsal { return selectedRehearsal?.state == .running }
    guard let selectedTransaction else { return false }
    if case .active = selectedTransaction.state { return true }
    return false
  }

  private var selectedIsInFlight: Bool {
    if mode == .simulatorRehearsal { return selectedRehearsal?.state == .running }
    guard let selectedTransaction else { return false }
    return switch selectedTransaction.state {
    case .active, .cancelling: true
    default: false
    }
  }

  private func isSucceeded(_ transaction: PreflightTransaction?) -> Bool {
    guard let transaction else { return false }
    if case .succeeded = transaction.state { return true }
    return false
  }

  private var selectedProgress: Double? {
    if mode == .simulatorRehearsal { return selectedRehearsal?.progress }
    return selectedTransaction?.progress
  }

  private var selectedCompletedStepCount: Int {
    if mode == .simulatorRehearsal { return selectedRehearsal?.completedStepCount ?? 0 }
    return selectedTransaction?.completedStepCount ?? 0
  }

  private var selectedCurrentStep: PreflightStep? {
    if mode == .simulatorRehearsal { return selectedRehearsal?.currentStep }
    return selectedTransaction?.currentStep
  }

  private func phaseLabel(for sequenceID: PreflightSequenceID) -> String {
    if mode == .simulatorRehearsal {
      return PreflightCalibrationPresentation.phaseLabel(for: rehearsals[sequenceID])
    }
    return PreflightCalibrationPresentation.phaseLabel(for: transactions[sequenceID])
  }

  private func phaseColor(for sequenceID: PreflightSequenceID) -> Color {
    if mode == .simulatorRehearsal {
      guard let rehearsal = rehearsals[sequenceID] else { return .secondary }
      return switch rehearsal.state {
      case .notStarted: .secondary
      case .running: .blue
      case .completed: .green
      case .cancelled: .secondary
      }
    }
    guard let transaction = transactions[sequenceID] else { return .secondary }
    return switch transaction.state {
    case .notStarted: .secondary
    case .active, .cancelling: .orange
    case .succeeded: .green
    case .failed: .red
    case .cancelled: .secondary
    }
  }
}
