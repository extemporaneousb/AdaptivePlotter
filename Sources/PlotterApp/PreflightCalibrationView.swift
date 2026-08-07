import PlotterRuntime
import SwiftUI

/// App-local labels for the runtime-owned preflight definitions.
///
/// `PlotterRuntime` owns sequence semantics, progress, evidence, and readiness.
/// This type only turns those typed values into compact operator-facing text.
enum PreflightCalibrationPresentation {
  static let title = "MOTION PREFLIGHT"
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
  let readiness: PreflightTrainingReadiness
  let startUnavailableReason: (PreflightSequenceID) -> String?
  let listeningStatus: String
  let errorText: String?
  let onStart: (PreflightSequenceID) -> Void
  let onCancel: (PreflightSequenceID) -> Void

  init(
    selectedSequenceID: Binding<PreflightSequenceID>,
    catalog: [PreflightSequenceDefinition] = PreflightSequenceCatalog.all,
    transactions: [PreflightSequenceID: PreflightTransaction],
    readiness: PreflightTrainingReadiness,
    startUnavailableReason: @escaping (PreflightSequenceID) -> String? = { _ in nil },
    listeningStatus: String = "Speech starts with a sequence.",
    errorText: String? = nil,
    onStart: @escaping (PreflightSequenceID) -> Void,
    onCancel: @escaping (PreflightSequenceID) -> Void
  ) {
    _selectedSequenceID = selectedSequenceID
    self.catalog = catalog
    self.transactions = transactions
    self.readiness = readiness
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
            .font(.headline.monospaced().bold())
          Text(PreflightCalibrationPresentation.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(readiness.isReady ? "READY TO TRAIN" : "PREFLIGHT")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(readiness.isReady ? Color.green : Color.orange)
      }

      HStack(spacing: 10) {
        ProgressView(
          value: Double(readiness.successfulSequenceClasses.count),
          total: Double(max(1, readiness.minimumSuccessfulSequenceClasses))
        )
        .frame(maxWidth: 260)

        Text(readinessSummary)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .background(.ultraThinMaterial)
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
    ScrollView {
      LazyVStack(spacing: 5) {
        ForEach(catalog) { definition in
          sequenceButton(definition)
        }
      }
      .padding(10)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
  }

  private func sequenceButton(_ definition: PreflightSequenceDefinition) -> some View {
    let transaction = transactions[definition.id]
    let selected = definition.id == selectedDefinition.id

    return Button {
      selectedSequenceID = definition.id
    } label: {
      HStack(spacing: 8) {
        Text(PreflightCalibrationPresentation.shortLabel(for: definition.id))
          .font(.caption.monospaced().bold())
          .frame(width: 42)
          .padding(.vertical, 6)
          .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))

        VStack(alignment: .leading, spacing: 3) {
          Text(PreflightCalibrationPresentation.title(for: definition.id))
            .font(.subheadline.weight(.semibold))
          Text(PreflightCalibrationPresentation.phaseLabel(for: transaction))
            .font(.caption2.monospaced().bold())
            .foregroundStyle(phaseColor(transaction))
        }

        Spacer(minLength: 0)
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selected ? Color.accentColor.opacity(0.22) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 7)
          .stroke(selected ? Color.accentColor.opacity(0.7) : Color.clear)
      }
    }
    .buttonStyle(.plain)
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

          Text(PreflightCalibrationPresentation.phaseLabel(for: selectedTransaction))
            .font(.caption.monospaced().bold())
            .foregroundStyle(phaseColor(selectedTransaction))
        }

        if let selectedTransaction {
          HStack(spacing: 10) {
            ProgressView(value: selectedTransaction.progress)
            Text("\(selectedTransaction.completedStepCount) / \(selectedDefinition.steps.count) events")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }

          if case .failed(let reason) = selectedTransaction.state {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
        }

        VStack(alignment: .leading, spacing: 5) {
          Text("REQUIRED VOICE PHRASE")
            .font(.caption2.monospaced().bold())
            .foregroundStyle(.secondary)
          Text(PreflightCalibrationPresentation.requiredVoicePhrase(for: selectedDefinition))
            .font(.body.monospaced().bold())
            .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 8) {
          Text("PARTICIPANTS · ACTIONS · EVENTS")
            .font(.caption2.monospaced().bold())
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
    let isCurrent = selectedTransaction?.currentStep?.id == step.id
    let isComplete = ordinal <= (selectedTransaction?.completedStepCount ?? 0)

    return HStack(alignment: .top, spacing: 9) {
      Image(systemName: isComplete ? "checkmark" : "\(ordinal).circle.fill")
        .font(.caption.monospaced().bold())
        .foregroundStyle(isCurrent ? Color.white : isComplete ? Color.green : Color.secondary)
        .frame(width: 22, height: 22)
        .background(isCurrent ? Color.accentColor : Color.clear, in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(step.participant.displayName.uppercased())
          .font(.caption2.monospaced().bold())
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
      Text("EVIDENCE / OUTPUT")
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      Text(PreflightCalibrationPresentation.expectedEvidenceOutput(for: selectedDefinition))
        .font(.callout)
      Divider()

      if let evidence = selectedTransaction?.evidenceSummaries, !evidence.isEmpty {
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
        Label(listeningStatus, systemImage: "mic.fill")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)

        if let reason = startUnavailableReason(selectedDefinition.id) {
          Text("Start unavailable: \(reason)")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        } else {
          Text("Start enables listening. Runtime checks retain controller authority.")
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

      Button("Cancel Sequence") {
        onCancel(selectedDefinition.id)
      }
      .disabled(!isActive(selectedTransaction))

      Button(isSucceeded(selectedTransaction) ? "Run Again" : "Start Sequence") {
        onStart(selectedDefinition.id)
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        isInFlight(selectedTransaction)
          || startUnavailableReason(selectedDefinition.id) != nil
      )
    }
    .padding(12)
    .background(.ultraThinMaterial)
  }

  private func isActive(_ transaction: PreflightTransaction?) -> Bool {
    guard let transaction else { return false }
    if case .active = transaction.state { return true }
    return false
  }

  private func isInFlight(_ transaction: PreflightTransaction?) -> Bool {
    guard let transaction else { return false }
    return switch transaction.state {
    case .active, .cancelling: true
    default: false
    }
  }

  private func isSucceeded(_ transaction: PreflightTransaction?) -> Bool {
    guard let transaction else { return false }
    if case .succeeded = transaction.state { return true }
    return false
  }

  private func phaseColor(_ transaction: PreflightTransaction?) -> Color {
    guard let transaction else { return .secondary }
    return switch transaction.state {
    case .notStarted: .secondary
    case .active: .orange
    case .cancelling: .orange
    case .succeeded: .green
    case .failed: .red
    case .cancelled: .secondary
    }
  }
}
