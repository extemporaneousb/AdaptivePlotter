import Foundation
import PlotterRuntime
import SwiftUI

/// Local ruler-entry state. Empty rows are preserved without inventing a measurement.
struct AxisMetricRulerDraft: Equatable {
  struct Row: Equatable {
    var length = ""
    var uncertainty = ""

    var isEmpty: Bool {
      length.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && uncertainty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var values: (length: Double, uncertainty: Double)? {
      guard let length = Double(length.trimmingCharacters(in: .whitespacesAndNewlines)),
        let uncertainty = Double(uncertainty.trimmingCharacters(in: .whitespacesAndNewlines)),
        length.isFinite, length > 0, uncertainty.isFinite, uncertainty >= 0, uncertainty < length
      else { return nil }
      return (length, uncertainty)
    }
  }

  var rows = Array(repeating: Row(), count: 4)
  var method = ""
  var axesConfirmed = false

  var validationMessage: String? {
    guard rows.contains(where: { !$0.isEmpty }) else {
      return "Enter at least one measured ink length and its uncertainty."
    }
    guard rows.allSatisfy({ $0.isEmpty || $0.values != nil }) else {
      return "Each entered segment needs a positive length and a nonnegative uncertainty smaller than the length in millimetres. Leave unmeasured segments blank."
    }
    guard !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "Record the independent measuring instrument and method."
    }
    return nil
  }
}

extension AxisMetricRulerDraft {
  init(measurement: ControllerAxisMetricMeasurement?) {
    self.init()
    guard let measurement else { return }
    for edge in measurement.edges {
      rows[edge.segmentIndex] = Row(length: String(edge.physicalLengthMM),
        uncertainty: String(edge.uncertaintyMM))
    }
    method = measurement.method
    axesConfirmed = measurement.operatorAxisAssociationConfirmed
  }

  func measurements() throws -> [ControllerAxisRulerMeasurement] {
    try rows.enumerated().compactMap { index, row in
      guard !row.isEmpty else { return nil }
      guard let values = row.values else { throw ControllerAxisMetricError.invalidMeasurement }
      return try ControllerAxisRulerMeasurement(segmentIndex: index,
        physicalLengthMM: values.length, uncertaintyMM: values.uncertainty)
    }
  }
}

/// An operator form over retained evidence. It neither derives calibration nor writes settings.
struct AxisMetricCalibrationView: View {
  let geometry: LearningFrameMetricGeometry?
  let latestMeasurement: ControllerAxisMetricMeasurement?
  let proposal: ControllerAxisCalibrationProposal?
  let status: String?
  let busy: Bool
  let applyUnavailableReason: String?
  let onSave: @MainActor ([ControllerAxisRulerMeasurement], String, Bool) async -> Void
  let onApply: @MainActor () async -> Void
  @State private var draft: AxisMetricRulerDraft
  @State private var localBusy = false
  @State private var entryError: String?

  init(geometry: LearningFrameMetricGeometry?, latestMeasurement: ControllerAxisMetricMeasurement?,
    proposal: ControllerAxisCalibrationProposal?, status: String?, busy: Bool,
    applyUnavailableReason: String?,
    onSave: @escaping @MainActor ([ControllerAxisRulerMeasurement], String, Bool) async -> Void,
    onApply: @escaping @MainActor () async -> Void
  ) {
    self.geometry = geometry; self.latestMeasurement = latestMeasurement
    self.proposal = proposal; self.status = status; self.busy = busy
    self.applyUnavailableReason = applyUnavailableReason
    self.onSave = onSave; self.onApply = onApply
    _draft = State(initialValue: AxisMetricRulerDraft(measurement:
      latestMeasurement?.geometry.recordID == geometry?.recordID ? latestMeasurement : nil))
  }

  private var savedDraft: AxisMetricRulerDraft {
    AxisMetricRulerDraft(measurement:
      latestMeasurement?.geometry.recordID == geometry?.recordID ? latestMeasurement : nil)
  }
  private var working: Bool { busy || localBusy }
  private var hasUnsavedChanges: Bool { draft != savedDraft }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Physical Axis Calibration").font(.headline)
      if let geometry {
        Text("Learning frame record \(geometry.recordID.rawValue.uuidString)")
          .font(.caption.monospaced()).textSelection(.enabled)
        Text("Planned controller geometry · controller completion recorded")
        Text("Spans include a separate ±0.001 mm nominal command-encoding allowance. This does not measure physical travel or orthogonality.").font(.caption).foregroundStyle(.secondary)
          .font(.subheadline)
        AxisMetricControllerDiagram(edges: geometry.edges)
        Text("Diagram uses controller coordinates: +X right, +Y up. It is not a photograph or proof of physical ink dimensions. Match the numbered segments to the drawn frame before measuring.")
          .font(.caption).foregroundStyle(.secondary)
        ForEach(geometry.edges, id: \.segmentIndex) { edge in
          rulerRow(edge)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Independent measuring instrument and method").font(.caption)
          TextField("Describe ruler or caliper, endpoints, and repeat readings", text: $draft.method,
            axis: .vertical)
            .lineLimit(2...4)
            .accessibilityIdentifier("axisMetric.method")
        }
        Toggle("I matched all four numbered ink segments to the signed controller axes.",
          isOn: $draft.axesConfirmed)
          .accessibilityIdentifier("axisMetric.axesConfirmed")
        Text("Save partial measurements now and add the remaining segments later. A proposal needs all four lengths, explicit uncertainty, confirmed axes, and compatible opposite sides.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Save Measurements") {
          guard !working else { return }
          entryError = draft.validationMessage
          guard entryError == nil else { return }
          do {
            let values = try draft.measurements()
            let method = draft.method
            let confirmed = draft.axesConfirmed
            localBusy = true
            Task { @MainActor in
              await onSave(values, method, confirmed)
              localBusy = false
            }
          } catch {
            entryError = "Uncertainty must be nonnegative and smaller than the measured length."
          }
        }
        .accessibilityIdentifier("axisMetric.save")
        if let entryError { Text(entryError).font(.caption).foregroundStyle(.red) }
        if let latestMeasurement, latestMeasurement.geometry.recordID == geometry.recordID {
          Text("Saved measurement \(latestMeasurement.measurementID.uuidString)")
            .font(.caption.monospaced()).textSelection(.enabled)
        }
        if let proposal {
          proposalReview(proposal)
        }
      } else {
        Text("Complete Learning Border to associate measurements with its exact recorded frame.")
          .foregroundStyle(.secondary)
      }
      if let status { Text(status).font(.caption).textSelection(.enabled) }
    }
    .textFieldStyle(.roundedBorder)
    .disabled(working)
    .onChange(of: geometry?.recordID) { _, _ in draft = savedDraft; entryError = nil }
    .onChange(of: latestMeasurement?.measurementID) { _, _ in draft = savedDraft; entryError = nil }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("axisMetric.section")
  }

  private func rulerRow(_ edge: LearningFrameMetricEdge) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(AxisMetricControllerDiagram.label(edge) + " · planned "
        + Self.millimetres(edge.plannedControllerSpanMM) + " mm")
        .font(.subheadline)
      Text("(\(Self.millimetres(edge.start.x)), \(Self.millimetres(edge.start.y))) → (\(Self.millimetres(edge.end.x)), \(Self.millimetres(edge.end.y))) controller mm")
        .font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Measured ink length (mm)").font(.caption)
          TextField("Unmeasured", text: $draft.rows[edge.segmentIndex].length)
            .accessibilityLabel("Segment \(edge.segmentIndex + 1) measured ink length in millimetres")
            .accessibilityIdentifier("axisMetric.length.\(edge.segmentIndex)")
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          Text("Uncertainty ± (mm)").font(.caption)
          TextField("Required", text: $draft.rows[edge.segmentIndex].uncertainty)
            .accessibilityLabel("Segment \(edge.segmentIndex + 1) uncertainty in millimetres")
            .accessibilityIdentifier("axisMetric.uncertainty.\(edge.segmentIndex)")
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func proposalReview(_ proposal: ControllerAxisCalibrationProposal) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      Text("Review firmware settings").font(.headline)
      Text("X  $100: \(String(proposal.oldXStepsPerMM)) → \(String(proposal.proposedXStepsPerMM)) steps/mm")
      Text("Y  $101: \(String(proposal.oldYStepsPerMM)) → \(String(proposal.proposedYStepsPerMM)) steps/mm")
      Text(proposal.commands.joined(separator: "\n"))
        .font(.caption.monospaced()).textSelection(.enabled)
      Text("Apply resets Boundary, camera, tip/contact, and Drawing Border Learning. Relearn them, then measure fresh independent holdout drawings. Axis scale calibration cannot correct skew, slip, or backlash.")
        .font(.caption).foregroundStyle(.secondary)
      if hasUnsavedChanges {
        Text("Save your changed measurements before applying a proposal.").font(.caption)
      }
      if let applyUnavailableReason { Text(applyUnavailableReason).font(.caption) }
      Button("Apply Axis Calibration") {
        guard !working, !hasUnsavedChanges, applyUnavailableReason == nil,
          proposal.measurementID == latestMeasurement?.measurementID,
          latestMeasurement?.geometry.recordID == geometry?.recordID else { return }
        localBusy = true
        Task { @MainActor in await onApply(); localBusy = false }
      }
      .disabled(hasUnsavedChanges || applyUnavailableReason != nil
        || proposal.measurementID != latestMeasurement?.measurementID
        || latestMeasurement?.geometry.recordID != geometry?.recordID)
      .accessibilityIdentifier("axisMetric.apply")
    }
  }

  private static func millimetres(_ value: Double) -> String { String(value) }
}

/// Aspect-preserving schematic of exact controller endpoints; no camera or physical evidence.
struct AxisMetricControllerDiagram: View {
  let edges: [LearningFrameMetricEdge]

  nonisolated static func label(_ edge: LearningFrameMetricEdge) -> String {
    "\(edge.segmentIndex + 1): \(edge.signedControllerDeltaMM > 0 ? "+" : "−")\(edge.axis.rawValue.uppercased())"
  }

  nonisolated static func segments(_ edges: [LearningFrameMetricEdge], size: CGSize) -> [(CGPoint, CGPoint)] {
    guard let minX = edges.map(\.start.x).min(), let maxX = edges.map(\.start.x).max(),
      let minY = edges.map(\.start.y).min(), let maxY = edges.map(\.start.y).max(),
      maxX > minX, maxY > minY else { return [] }
    let scale = min(max(0, size.width - 100) / (maxX - minX),
      max(0, size.height - 60) / (maxY - minY))
    func point(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x: size.width / 2 + (x - (minX + maxX) / 2) * scale,
        y: size.height / 2 - (y - (minY + maxY) / 2) * scale)
    }
    return edges.map { (point($0.start.x, $0.start.y), point($0.end.x, $0.end.y)) }
  }

  var body: some View {
    GeometryReader { geometry in
      let segments = Self.segments(edges, size: geometry.size)
      ZStack {
        Path { path in
          for (start, end) in segments { path.move(to: start); path.addLine(to: end) }
        }.stroke(.secondary, lineWidth: 1.5)
        ForEach(Array(edges.enumerated()), id: \.element.segmentIndex) { index, edge in
          if index < segments.count {
            let pair = segments[index]
            let dx: CGFloat = edge.axis == .y ? (edge.signedControllerDeltaMM > 0 ? -27 : 27) : 0
            let dy: CGFloat = edge.axis == .x ? (edge.signedControllerDeltaMM > 0 ? -15 : 15) : 0
            Text(Self.label(edge)).font(.caption.monospaced())
              .position(x: (pair.0.x + pair.1.x) / 2 + dx,
                y: (pair.0.y + pair.1.y) / 2 + dy)
          }
        }
      }
    }
    .frame(height: 200)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Controller-coordinate schematic. Positive X points right. Positive Y points up. "
      + edges.map(Self.label).joined(separator: ", "))
    .accessibilityIdentifier("axisMetric.diagram")
  }
}
