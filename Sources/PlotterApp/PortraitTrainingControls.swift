import SwiftUI

/// Quiet controls for the existing training and Studio owners. Local state is
/// limited to unsubmitted names, picker selection and action feedback.
struct PortraitTrainingControls: View {
  let model: PortraitStudioModel
  @State private var newName = ""
  @State private var newMode: PortraitTrainingScopeDefinition.Mode = .drawingStyle
  @State private var newObjective: PortraitLabelObjective = .screenAesthetic
  @State private var selectedCheckpointID: String?
  @State private var message: String?
  @State private var actionInFlight = false

  private var library: PortraitTrainingLibrary { model.training }
  private var definition: PortraitTrainingScopeDefinition? {
    library.scope(model.selectedStyleScope.id)
  }
  private var scopes: [PortraitStyleScope] {
    let saved = library.scopes.map(\.scope)
    var values = saved.contains(where: { $0.id == PortraitStyleScope.screenSketch.id })
      ? saved : [.screenSketch] + saved
    if !values.contains(where: { $0.id == model.selectedStyleScope.id }) {
      values.append(model.selectedStyleScope)
    }
    return values
  }
  private var checkpoints: [PortraitPreferenceCheckpoint] {
    library.checkpoints.filter { $0.scopeID == model.selectedStyleScope.id }
  }
  private var active: PortraitPreferenceCheckpoint? {
    library.activeCheckpoint(for: model.selectedStyleScope.id)
  }
  private var picked: PortraitPreferenceCheckpoint? {
    if let selectedCheckpointID,
      let checkpoint = checkpoints.first(where: { $0.id == selectedCheckpointID }) { return checkpoint }
    if let pending = library.pendingCheckpointID,
      let checkpoint = checkpoints.first(where: { $0.id == pending }) { return checkpoint }
    return active ?? checkpoints.last
  }
  private var pickedIsCompatible: Bool {
    guard let definition, let picked else { return false }
    return picked.payload.dataset.payload.scope == definition
  }
  private var busy: Bool { actionInFlight || library.isWorking || model.isProcessing }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Named style training").font(.headline)
      Picker("Rating and training scope", selection: Binding(
        get: { model.selectedStyleScope.id },
        set: { id in
          if let scope = scopes.first(where: { $0.id == id }) {
            model.selectedStyleScope = scope
            selectedCheckpointID = nil
            message = nil
          }
        })) {
          ForEach(scopes) { scope in Text(scope.name).tag(scope.id) }
        }
        .disabled(busy)
        .accessibilityIdentifier("portrait.training.scope")
      scopeDetails
      creationControls
      HStack {
        Button(active == nil ? "Train Style" : "Update Style") {
          perform { await model.trainSelectedStyle() }
        }
        .disabled(busy || !model.canTrainSelectedStyle || !library.canWrite)
        .accessibilityIdentifier("portrait.training.fit")
        if library.isFitting {
          Button("Cancel Fit") { library.cancel() }
            .accessibilityIdentifier("portrait.training.cancel")
        }
        Button(definition?.mode == .semanticBigHead ? "Vary Big Head" : "Explore This Style") {
          model.exploreSelectedStyle()
        }
        .disabled(busy || definition == nil || !model.canRateSelection)
        .accessibilityIdentifier("portrait.training.explore")
      }
      if definition == nil {
        Text(model.selectedStyleScope.id == PortraitStyleScope.screenSketch.id
          ? "Train Style uses the existing ratings in this default scope and saves its configuration."
          : "Create a named style from a completed drawing to choose its active and fixed parameters.")
          .font(.caption).foregroundStyle(.secondary)
      }
      checkpointControls
      if let picked { evaluation(picked) }
      if let comparison = model.trainingComparison,
        library.checkpoint(comparison.checkpointID)?.scopeID == model.selectedStyleScope.id {
        comparisonControls(comparison)
      }
      Text(library.status).font(.caption).textSelection(.enabled)
        .accessibilityIdentifier("portrait.training.status")
      if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      if !library.issues.isEmpty {
        DisclosureGroup("Training evidence and storage details") {
          ForEach(Array(library.issues.enumerated()), id: \.offset) { item in
            Text(item.element).font(.caption).textSelection(.enabled)
          }
        }
      }
      Button("Reload Training Storage") { perform { await library.load() } }
        .disabled(busy)
        .accessibilityIdentifier("portrait.training.reload")
    }
    .accessibilityIdentifier("portrait.training.controls")
  }

  private var scopeDetails: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(objectiveName(model.selectedStyleScope.objective))
      Text("Active: " + model.selectedStyleScope.activeParameters.map(parameterName).joined(separator: ", "))
      Text("Fixed: " + frozenDescription)
      Text("Families: " + model.selectedStyleScope.allowedFamilies.map(\.rawValue).joined(separator: ", "))
      if definition?.mode == .semanticBigHead {
        Text("Big Head exploration keeps the selected source, crop and line style fixed.")
      }
    }.font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
  }

  private var frozenDescription: String {
    let values = model.selectedStyleScope.frozenParameters
    guard !values.isEmpty else { return "None declared" }
    return values.map { parameterName($0.parameter) + " " + $0.value.formatted(.number.precision(.fractionLength(0...3))) }
      .joined(separator: ", ")
  }

  private var creationControls: some View {
    DisclosureGroup("Create Named Style") {
      VStack(alignment: .leading, spacing: 8) {
        TextField("Style name", text: $newName)
          .accessibilityIdentifier("portrait.training.newName")
        Picker("Parameters to explore", selection: $newMode) {
          Text("Drawing style").tag(PortraitTrainingScopeDefinition.Mode.drawingStyle)
          Text("Semantic Big Head").tag(PortraitTrainingScopeDefinition.Mode.semanticBigHead)
        }.accessibilityIdentifier("portrait.training.newMode")
        Picker("Rating objective", selection: $newObjective) {
          Text("Screen appearance").tag(PortraitLabelObjective.screenAesthetic)
          Text("Physical drawing").tag(PortraitLabelObjective.physicalRealization)
        }.accessibilityIdentifier("portrait.training.newObjective")
        Text(newObjective == .screenAesthetic
          ? "Fit the ratings of the displayed candidates in this scope."
          : "Fit ratings linked to photographed physical attempts. Screen ratings stay separate.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Create from Selected Drawing") {
          let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
          let mode = newMode, objective = newObjective
          perform {
            message = await model.createTrainingScope(name: name, mode: mode, objective: objective)
            if message == nil { newName = "" }
          }
        }
        .disabled(busy || !library.canWrite || !model.canRateSelection
          || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("portrait.training.create")
      }.padding(.top, 5)
    }
  }

  private var checkpointControls: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(active.map { "Active checkpoint: " + shortID($0.id) } ?? "Active: renderer prior")
        .font(.caption).textSelection(.enabled)
      if let pending = library.pendingCheckpointID,
        checkpoints.contains(where: { $0.id == pending }), pending != active?.id {
        Text("Pending checkpoint: " + shortID(pending) + " · saved, awaiting activation")
          .font(.caption).foregroundStyle(.secondary)
      }
      if !checkpoints.isEmpty {
        Picker("Checkpoint to inspect", selection: Binding(
          get: { picked?.id ?? "" }, set: { selectedCheckpointID = $0 })) {
            ForEach(checkpoints) { checkpoint in
              Text(checkpointLabel(checkpoint)).tag(checkpoint.id)
            }
          }
          .disabled(busy)
          .accessibilityIdentifier("portrait.training.checkpoint")
        HStack {
          Button("Compare with Prior") {
            guard let picked else { return }
            model.compareSelectedStyle(checkpointID: picked.id)
          }
          .disabled(busy || !pickedIsCompatible || !model.canRateSelection)
          .accessibilityIdentifier("portrait.training.compare")
          Button("Activate") {
            guard let picked else { return }
            perform { await model.activateStyleCheckpoint(picked.id) }
          }
          .disabled(busy || !library.canWrite || !pickedIsCompatible || picked?.id == active?.id)
          .accessibilityIdentifier("portrait.training.activate")
        }
        if !pickedIsCompatible {
          Text("This checkpoint does not match the selected scope configuration.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      HStack {
        Button("Use Renderer Prior") { perform { await model.activateStyleCheckpoint(nil) } }
          .disabled(busy || !library.canWrite || active == nil)
          .accessibilityIdentifier("portrait.training.prior")
        Button("Roll Back") { perform { await model.rollbackStyleCheckpoint() } }
          .disabled(busy || !library.canWrite || active == nil)
          .accessibilityIdentifier("portrait.training.rollback")
      }
      Text("Activation changes future generation. Updates use a deterministic full refit with a reset optimizer and record the completed parent.")
        .font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func evaluation(_ checkpoint: PortraitPreferenceCheckpoint) -> some View {
    let result = checkpoint.payload.evaluation
    return DisclosureGroup("Checkpoint evidence · " + shortID(checkpoint.id)) {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(result.trainingCount) training labels in \(result.trainingGroupCount) groups · \(result.holdoutCount) holdout labels in \(result.holdoutGroupCount) groups")
        Text("Ordinal loss · training \(result.trainingLoss, specifier: "%.4f")")
        if let loss = result.holdoutLoss {
          Text("Holdout loss \(loss, specifier: "%.4f")")
        } else { Text("Independent holdout loss unavailable.") }
        if let loss = result.priorHoldoutLoss { Text("Prior holdout loss \(loss, specifier: "%.4f")") }
        if let accuracy = result.withinSourceOrderingAccuracy {
          Text("Within-source ordering \(accuracy * 100, specifier: "%.1f")% · \(result.comparablePairCount) comparable pairs")
        } else { Text("Within-source ordering unavailable; no comparable held-out pairs.") }
        Text("\(checkpoint.payload.completedIterations) iterations · \(checkpoint.payload.converged ? "converged" : "iteration limit reached")")
        Text("Parent: " + (checkpoint.payload.parentCheckpointID.map(shortID) ?? "renderer prior"))
        let retainedIDs = Set(model.sketches.entries.map(\.id))
        let missing = Set(checkpoint.payload.dataset.payload.rows.map(\.candidateID)).subtracting(retainedIDs)
        if !missing.isEmpty {
          Text("\(missing.count) historical candidates are no longer available in the drawing archive. This checkpoint retains its frozen labels and features; original images and exact candidate replay are unavailable for those entries.")
        }

        ForEach(Array(result.limitations.enumerated()), id: \.offset) { item in Text(item.element) }
        Text("These metrics describe the recorded labels. Human likeness and physical drawing quality require separate evidence.")
      }.font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 4)
    }
  }

  private func comparisonControls(_ comparison: PortraitTrainingComparison) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Prior / checkpoint comparison").font(.caption).bold()
      HStack(alignment: .top, spacing: 10) {
        VStack {
          PortraitProgramPreview(program: comparison.prior.program).frame(minHeight: 130, maxHeight: 180)
          Button("Select Prior Candidate") { model.selectTrainingComparison(current: false) }
            .accessibilityIdentifier("portrait.training.selectPrior")
        }
        VStack {
          PortraitProgramPreview(program: comparison.current.program).frame(minHeight: 130, maxHeight: 180)
          Button("Select Checkpoint Candidate") { model.selectTrainingComparison(current: true) }
            .accessibilityIdentifier("portrait.training.selectCurrent")
        }
      }.disabled(busy)
      Text(comparison.summary).font(.caption).foregroundStyle(.secondary)
      Text("Checkpoint \(shortID(comparison.checkpointID)) · shared seed \(String(comparison.seed))")
        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
      Text("Select a candidate to inspect and rate it in the Studio. Physical ratings require a linked photographed attempt.")
        .font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func perform(_ action: @escaping @MainActor () async -> Void) {
    guard !actionInFlight else { return }
    actionInFlight = true
    Task { await action(); actionInFlight = false }
  }

  private func shortID(_ id: String) -> String { String(id.prefix(10)) }
  private func checkpointLabel(_ checkpoint: PortraitPreferenceCheckpoint) -> String {
    shortID(checkpoint.id) + " · " + String(checkpoint.payload.evaluation.trainingCount) + " labels"
      + (checkpoint.id == active?.id ? " · active" : "")
  }
  private func objectiveName(_ objective: PortraitLabelObjective) -> String {
    objective == .screenAesthetic ? "Screen appearance ratings" : "Physical drawing ratings"
  }
  private func parameterName(_ parameter: PortraitTrainableParameter) -> String {
    switch parameter {
    case .contourLevels: "contour levels"
    case .minimumContourLength: "minimum contour length"
    case .simplificationTolerance: "simplification"
    case .hatchSpacing: "hatch spacing"
    case .tonalStrength: "tonal strength"
    case .smoothing: "smoothing"
    case .sketchThreshold: "line threshold"
    case .hatchAngleDegrees: "hatch angle"
    case .headScale: "legacy head scale"
    case .foreheadWidth: "forehead width"
    case .foreheadHeight: "forehead height"
    case .eyeScale: "eye size"
    case .lateralScale: "lateral head size"
    }
  }
}
