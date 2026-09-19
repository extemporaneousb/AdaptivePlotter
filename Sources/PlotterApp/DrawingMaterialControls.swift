import PlotterModel
import PlotterRuntime
import SwiftUI

/// Select the pen here; measuring it and adapting artwork remain explicit actions.
struct DrawingMaterialControls: View {
  let library: DrawingMaterialLibrary
  let currentApplicability: DrawingMaterialApplicability?
  let measurementStatus: String?
  var canMeasureExistingInk = true
  var canApply = true
  let measure: () async -> String?
  let apply: (DrawingMaterialProfileRevision) async -> String?
  var verifyMedia: (DrawingMaterialRecord) async -> String? = { _ in nil }
  @State private var mediaStatus: String?
  @State private var materialName = ""
  @State private var nominalWidthMM = 0.8
  @State private var actionStatus: String?
  @State private var actionInProgress = false
  @State private var managesMaterials = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker("Pen", selection: Binding(get: { library.activeKey ?? "" }, set: { key in
          actionStatus = key.isEmpty ? library.deactivate() : library.activate(key: key)
        })) {
          Text("Program nominal width").tag("")
          ForEach(library.records, id: \.profile.key) { record in
            Text(record.profile.name).tag(record.profile.key)
          }
        }.accessibilityIdentifier("drawing.material.selection")
        Button { managesMaterials = true } label: { Image(systemName: "ellipsis.circle") }
          .accessibilityLabel("Manage materials")
          .popover(isPresented: $managesMaterials) { management }
      }
      if let record = library.activeRecord {
        HStack {
          Text("\(record.profile.conservativeWidthMM, specifier: "%.2f") mm")
            .monospacedDigit()
          Text(qualification(record.profile.qualification)).foregroundStyle(.secondary)
          Spacer()
          StudioHelpButton("Marker thickness", text: details(record))
        }.font(.caption)
        PortraitAdaptiveRow {
          Button("Measure Ink") { perform { await measure() } }
            .disabled(actionInProgress || !canMeasureExistingInk)
            .accessibilityIdentifier("drawing.material.measure")
          Button("Adapt Detail") {
            let profile = record.profile
            perform { await apply(profile) }
          }
          .disabled(actionInProgress || !canApply)
          .accessibilityIdentifier("drawing.material.apply")
          StudioHelpButton("Pen and drawing", text: "Measure Ink estimates deposited width from existing images after inspection. Adapt Detail creates a new portrait drawing with spacing suited to that width at its current size. It changes the artwork, not the learned calibration.")
        }
      }
      if actionInProgress { ProgressView().controlSize(.small) }
      if let actionStatus {
        HStack {
          Text("Material action needs attention").font(.caption)
          StudioHelpButton("Material action", text: actionStatus)
        }
      }
      if library.persistenceError != nil {
        HStack {
          Button("Retry Save") { Task { await library.retry() } }
            .accessibilityIdentifier("drawing.material.retry")
          StudioHelpButton("Material storage", text: library.storageStatus)
        }
      }
    }
    .task { await library.load() }
    .task(id: library.activeKey) {
      mediaStatus = nil
      guard let record = library.activeRecord else { return }
      let result = await verifyMedia(record)
      guard !Task.isCancelled, library.activeKey == record.profile.key else { return }
      mediaStatus = result
    }
  }

  private var management: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Materials").font(.headline)
      TextField("Name", text: $materialName).accessibilityIdentifier("drawing.material.name")
      HStack {
        Text("Nominal width (mm)")
        TextField("Width", value: $nominalWidthMM, format: .number.precision(.fractionLength(2)))
          .frame(width: 80).accessibilityIdentifier("drawing.material.nominalWidth")
      }
      Button("Create Nominal") {
        actionStatus = library.createNominal(name: materialName, widthMM: nominalWidthMM)
        if actionStatus == nil { materialName = ""; managesMaterials = false }
      }
      .disabled(materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !nominalWidthMM.isFinite || nominalWidthMM <= 0)
      .accessibilityIdentifier("drawing.material.createNominal")
      if let record = library.activeRecord {
        Button("Delete Selected Revision", role: .destructive) {
          actionStatus = library.delete(key: record.profile.key)
          if actionStatus == nil { managesMaterials = false }
        }.accessibilityIdentifier("drawing.material.delete")
      }
      StudioHelpButton("Material revisions", text: "Nominal width is an estimate. Measured width is bound to its recorded calibration, paper and pen settings. Deleting a library revision leaves immutable drawings and execution evidence unchanged.")
    }.padding(16).frame(width: 320)
  }

  private func perform(_ operation: @escaping () async -> String?) {
    actionInProgress = true
    Task { actionStatus = await operation(); actionInProgress = false }
  }

  private func details(_ record: DrawingMaterialRecord) -> String {
    var values = ["\(record.profile.name), revision \(record.profile.revision)."]
    if let bound = record.applicability {
      values.append(bound == currentApplicability
        ? "Measurement settings match the current calibration, paper and actuation."
        : "Measurement applicability has expired or is unavailable for the current setup.")
    } else { values.append("Nominal settings; deposited behavior has not been measured.") }
    if let distribution = record.profile.depositedWidth {
      values.append(String(format: "Deposited width %.2f–%.2f mm; uncertainty ±%.2f mm; %d samples.",
        distribution.lowerBoundMM, distribution.upperBoundMM, distribution.uncertaintyMM, distribution.sampleCount))
      values += distribution.directional.map {
        String(format: "%.0f°: %.2f ±%.2f mm (%d samples).", $0.directionRadians * 180 / .pi,
          $0.medianMM, $0.uncertaintyMM, $0.sampleCount)
      }
    }
    values += record.measurement?.limitations ?? []
    values += [measurementStatus, mediaStatus].compactMap { $0 }
    return values.joined(separator: "\n\n")
  }

  private func qualification(_ value: MaterialWidthQualification) -> String {
    switch value {
    case .nominal: "estimated"
    case .controllerCoordinateEstimate: "camera estimate"
    case .independentlyMeasured: "measured"
    case .bounded: "bounded estimate"
    case .unavailable: "unavailable"
    }
  }
}
