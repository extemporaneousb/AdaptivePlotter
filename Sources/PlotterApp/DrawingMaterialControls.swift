import PlotterModel
import PlotterRuntime
import SwiftUI

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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Drawing Material").font(.headline)
      Picker("Material", selection: Binding(get: { library.activeKey ?? "" }, set: { key in
        actionStatus = key.isEmpty ? library.deactivate() : library.activate(key: key)
      })) {
        Text("No active material — use nominal pen settings").tag("")
        ForEach(library.records, id: \.profile.key) { record in
          Text("\(record.profile.name) · revision \(record.profile.revision)").tag(record.profile.key)
        }
      }
      .accessibilityIdentifier("drawing.material.selection")
      HStack {
        TextField("Material name", text: $materialName)
          .accessibilityIdentifier("drawing.material.name")
        TextField("Nominal width, mm", value: $nominalWidthMM, format: .number.precision(.fractionLength(2)))
          .frame(width: 90)
          .accessibilityIdentifier("drawing.material.nominalWidth")
        Button("Create Nominal") {
          actionStatus = library.createNominal(name: materialName, widthMM: nominalWidthMM)
          if actionStatus == nil { materialName = "" }
        }
        .disabled(materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !nominalWidthMM.isFinite || nominalWidthMM <= 0)
        .accessibilityIdentifier("drawing.material.createNominal")
      }
      if let record = library.activeRecord {
        Text("\(qualification(record.profile.qualification)) · nominal \(record.profile.nominalWidthMM, format: .number.precision(.fractionLength(2))) mm")
          .font(.caption)
        Text(applicability(record)).font(.caption).foregroundStyle(.secondary)
        if let distribution = record.profile.depositedWidth {
          Text("Deposited width \(distribution.lowerBoundMM, format: .number.precision(.fractionLength(2)))–\(distribution.upperBoundMM, format: .number.precision(.fractionLength(2))) mm; uncertainty ±\(distribution.uncertaintyMM, format: .number.precision(.fractionLength(2))) mm; \(distribution.sampleCount) samples")
            .font(.caption)
          DisclosureGroup("Directional widths and evidence") {
            ForEach(Array(distribution.directional.enumerated()), id: \.offset) { _, direction in
              Text("\(direction.directionRadians * 180 / .pi, format: .number.precision(.fractionLength(0)))°: \(direction.medianMM, format: .number.precision(.fractionLength(2))) ±\(direction.uncertaintyMM, format: .number.precision(.fractionLength(2))) mm (\(direction.sampleCount) samples)")
                .font(.caption2)
            }
            if let measurement = record.measurement {
              ForEach(Array(measurement.limitations.enumerated()), id: \.offset) { _, limitation in
                Text(limitation).font(.caption2).foregroundStyle(.secondary)
              }
            }
            Text("This material archive retains measurement references and geometry. Durable raw-image retention for these measurements is pending the drawing-run archive integration; references alone do not retain images.")
              .font(.caption2).foregroundStyle(.secondary)
          }
        }
        HStack {
          Button("Measure Existing Ink") { perform { await measure() } }
            .disabled(actionInProgress || !canMeasureExistingInk)
            .accessibilityIdentifier("drawing.material.measure")
            .help("Inspect exact existing images before confirming unobstructed mark visibility. This does not move the plotter or draw a new mark.")
          Button("Apply to Drawing at Current Scale") {
            let profile = record.profile
            perform { await apply(profile) }
          }
          .disabled(actionInProgress || !canApply)
          .accessibilityIdentifier("drawing.material.apply")
        }
        Button("Delete This Material Revision", role: .destructive) {
          actionStatus = library.delete(key: record.profile.key)
        }
        .font(.caption)
        .accessibilityIdentifier("drawing.material.delete")
        .help("Remove this library entry and clear its active selection. Retained drawings preserve their own material revision.")
      }
      if let mediaStatus { Text(mediaStatus).font(.caption).foregroundStyle(.secondary) }
      if let measurementStatus { Text(measurementStatus).font(.caption).foregroundStyle(.secondary) }
      if let actionStatus { Text(actionStatus).font(.caption).foregroundStyle(.secondary) }
      HStack {
        Text(library.storageStatus).font(.caption2).foregroundStyle(.secondary)
        if library.persistenceError != nil {
          Button("Retry Save") { Task { await library.retry() } }
            .accessibilityIdentifier("drawing.material.retry")
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

  private func perform(_ operation: @escaping () async -> String?) {
    actionInProgress = true
    Task {
      actionStatus = await operation()
      actionInProgress = false
    }
  }

  private func applicability(_ record: DrawingMaterialRecord) -> String {
    guard let bound = record.applicability else { return "Unbound nominal settings. No measured material behavior is established." }
    guard let currentApplicability else { return "Applicability unavailable: current calibration, paper and actuation inputs are incomplete." }
    return bound == currentApplicability
      ? "Declared measurement settings match the current calibration, paper and actuation."
      : "Measurement applicability has expired for the current calibration, paper or actuation."
  }

  private func qualification(_ value: MaterialWidthQualification) -> String {
    switch value {
    case .nominal: "Nominal width"
    case .controllerCoordinateEstimate: "Estimated in controller coordinates"
    case .independentlyMeasured: "Independently measured width"
    case .bounded: "Bounded width"
    case .unavailable: "Measured width unavailable"
    }
  }
}
