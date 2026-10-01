import PlotterModel
import SwiftUI

/// Framing and algorithm tuning share the drawing's visible editing surface.
struct PortraitRenderControls: View {
  @Bindable var model: PortraitStudioModel

  let strokeStyle: PlotterModel.StrokeStyle
  @Binding var showsAdvanced: Bool
  @State private var savingStyle = false
  @State private var styleName = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Parameters").font(.headline)
      Picker("Drawing style", selection: Binding(get: { model.style },
        set: { model.selectStyle($0, strokeStyle: strokeStyle) })) {
        ForEach(PortraitStyle.authoringCases) { Text($0.rawValue).tag($0) }
        if !PortraitStyle.authoringCases.contains(model.style) {
          Text(model.style.rawValue).tag(model.style)
        }
      }
      .accessibilityIdentifier("portrait.style")
      .disabled(model.isCapturing)
      HStack {
        PortraitSavedStylesView(model: model, strokeStyle: strokeStyle)
        Spacer(minLength: 0)
        Button("Save Style") {
          styleName = model.selectedCandidate?.recipe.title ?? "My style"
          savingStyle = true
        }
        .disabled(model.selectedCandidate == nil || model.isProcessing || model.isCapturing || model.isExploring)
        .accessibilityIdentifier("portrait.saveStyle")
        .popover(isPresented: $savingStyle) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Save reusable recipe").font(.headline)
            TextField("Style name", text: $styleName)
            HStack {
              Button("Cancel") { savingStyle = false }
                .accessibilityIdentifier("portrait.cancelSaveStyle")
              Spacer()
              Button("Save Style") { model.saveStyle(name: styleName); savingStyle = false }
                .disabled(styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }.padding(12).frame(width: 260)
        }
      }
      Divider()
      Picker("Feature", selection: $model.explorationRegion) {
        Text("Whole portrait").tag(Optional<PortraitTreatmentRegion>.none)
        ForEach(PortraitTreatmentRegion.allCases) { Text($0.rawValue).tag(Optional($0)) }
      }
      .accessibilityIdentifier("portrait.exploration.region")
      .disabled(model.isCapturing)
      if let region = model.explorationRegion {
        HStack {
          Text(region.rawValue).font(.headline)
          Spacer()
          StudioHelpButton("Feature adjustments", text: "These landmark-based controls edit the selected feature in every drawing style. Next varies the same settings. Other features and framing stay fixed.")
        }
        PortraitAdjustmentSlider("Protection", value: regionalBinding(\.featureProtection, region: region),
          range: 0...1, step: 0.05, unit: "")
        PortraitAdjustmentSlider("Angularity", value: regionalBinding(\.angularity, region: region),
          range: 0...1, step: 0.05, unit: "")
        PortraitAdjustmentSlider("Shadows", value: regionalBinding(\.shadowStrength, region: region),
          range: 0...1, step: 0.05, unit: "")
        PortraitAdjustmentSlider("Emphasis", value: regionalBinding(\.contourEmphasis, region: region),
          range: 0...1, step: 0.05, unit: "")
        if region == .face || region == .skin {
          PortraitAdjustmentSlider("Skin cleanup", value: regionalBinding(\.skinSuppression, region: region),
            range: 0...1, step: 0.05, unit: "")
        }
      } else {
        HStack {
          Text("Drawing").font(.headline)
          Spacer()
          StudioHelpButton("Drawing parameters", text: "Detail, tone, smoothness and minimum line length use the same recipe coordinates in every style. Each renderer translates them into its own curves. Spatial settings are relative to image height. Next varies these same parameters; selecting a style keeps them. Older saved recipes keep their original settings until edited.")
        }
        if model.vectorOptions.drawingParameters == nil {
          Text("Original recipe retained until you edit drawing parameters.")
            .font(.caption).foregroundStyle(.secondary)
        }
        PortraitAdjustmentSlider("Detail", value: drawingBinding(\.detail), range: 0...1, step: 0.05, unit: "")
        PortraitAdjustmentSlider("Tone", value: drawingBinding(\.tone), range: 0.4...2, step: 0.05, unit: "×")
        PortraitAdjustmentSlider("Smoothness", value: drawingBinding(\.smoothness), range: 0...1, step: 0.05, unit: "")
        PortraitAdjustmentSlider("Min. line", value: drawingBinding(\.minimumLine, scale: 100),
          range: 0...7.5, step: 0.25, unit: "%", precision: 2)
        HStack(spacing: 5) {
          ForEach(PortraitVectorPreset.allCases, id: \.self) { preset in
            Button(preset == .broadMarker ? "Coarse" : preset.rawValue) { model.applyDetailPreset(preset) }
              .accessibilityIdentifier("portrait.preset.\(preset.rawValue)")
          }
          Spacer(minLength: 0)
          Button("Reset") { model.resetStyle(model.style, strokeStyle: strokeStyle) }
            .help("Reset drawing and feature parameters, keeping photo framing and material")
            .accessibilityIdentifier("portrait.resetParameters")
        }
      }
      Text(model.parameterPreferenceReport?.summary
        ?? "Promising/rejected feedback can tune Next once independent photo comparisons support it.")
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityIdentifier("portrait.parameterLearning")
      Divider()
      HStack {
        Text("Framing").font(.headline)
        Spacer()
        StudioHelpButton("Framing", text: "Crop and background removal apply to this photo in every style. Head margin controls how much hair and shoulder area surrounds the face.")
      }
      Toggle("Crop to face", isOn: $model.options.cropToFace)
        .accessibilityIdentifier("portrait.cropToFace")
      if model.options.cropToFace {
        PortraitAdjustmentSlider("Head margin", value: $model.options.faceCropMargin,
          range: 0.05...0.8, step: 0.05, unit: "×")
      }
      Toggle("Remove background", isOn: $model.options.removeBackground)
        .accessibilityIdentifier("portrait.removeBackground")
      if model.style == .flowEdges {
        DisclosureGroup("Flow Edge options", isExpanded: $showsAdvanced) {
          VStack(alignment: .leading, spacing: 4) {
            Picker("Line form", selection: Binding(
              get: { FlowLineForm(value: model.vectorOptions.flowRectilinearity ?? 0) },
              set: { model.vectorOptions.flowRectilinearity = $0.value })) {
              ForEach(FlowLineForm.allCases, id: \.self) { form in Text(form.rawValue).tag(form) }
            }
            .accessibilityIdentifier("portrait.flowLineForm")
            PortraitAdjustmentSlider("Tone support", value: flowBinding(\.flowSupport),
              range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSupport")
            PortraitAdjustmentSlider("Persistence", value: flowBinding(\.flowStructureSupport),
              range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowStructureSupport")
            PortraitAdjustmentSlider("Evidence scale", value: flowBinding(\.flowSupportScale),
              range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSupportScale")
              .disabled((model.vectorOptions.flowSupport ?? 0) == 0 && (model.vectorOptions.flowStructureSupport ?? 0) == 0)
            PortraitAdjustmentSlider("Irregularity", value: flowBinding(\.flowSeedIrregularity),
              range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSeedIrregularity")
          }.padding(.top, 4)
        }
        .accessibilityIdentifier("portrait.adjustmentsDisclosure")
      }
    }
    .controlSize(.small)
    .disabled(model.isCapturing)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.adjustments")
  }

  private func drawingBinding(_ keyPath: WritableKeyPath<PortraitDrawingParameters, Double>,
    scale: Double = 1) -> Binding<Double> {
    Binding(get: { model.drawingParameters[keyPath: keyPath] * scale }, set: { value in
      var parameters = model.drawingParameters
      parameters[keyPath: keyPath] = value / scale
      model.drawingParameters = parameters
    })
  }

  private func regionalBinding(_ keyPath: WritableKeyPath<PortraitRegionalParameters, Double>,
    region: PortraitTreatmentRegion) -> Binding<Double> {
    Binding(get: { model.vectorOptions.treatment(for: region)[keyPath: keyPath] }, set: { value in
      var treatment = model.vectorOptions.treatment(for: region)
      treatment[keyPath: keyPath] = value
      model.vectorOptions.setTreatment(treatment)
    })
  }

  private func flowBinding(_ keyPath: WritableKeyPath<PortraitVectorOptions, Double?>) -> Binding<Double> {
    Binding(get: { model.vectorOptions[keyPath: keyPath] ?? 0 },
      set: { model.vectorOptions[keyPath: keyPath] = PortraitVectorOptions.flowAmount($0) })
  }
}

private enum FlowLineForm: String, CaseIterable {
  case organic = "Organic", mixed = "Mixed", rectilinear = "Rectilinear"

  init(value: Double) { self = value < 0.25 ? .organic : value < 0.75 ? .mixed : .rectilinear }
  var value: Double? {
    switch self { case .organic: nil; case .mixed: 0.5; case .rectilinear: 1 }
  }
}

/// Commit a drag once on release; keyboard edits commit immediately.
struct PortraitAdjustmentSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let unit: String
  var precision = 2
  var identifier: String?
  @State private var draft: Double?
  @State private var isEditing = false

  init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
       unit: String, precision: Int = 2, identifier: String? = nil) {
    self.title = title
    _value = value
    self.range = range
    self.step = step
    self.unit = unit
    self.precision = precision
    self.identifier = identifier
  }

  var body: some View {
    HStack(spacing: 6) {
      Text(title).frame(width: 92, alignment: .leading)
      Slider(value: Binding(get: { draft ?? value }, set: { proposed in
        let rounded = min(range.upperBound, max(range.lowerBound, (proposed/step).rounded()*step))
        draft = rounded
        if !isEditing { value = rounded; draft = nil }
      }), in: range, onEditingChanged: { editing in
        isEditing = editing
        if !editing, let draft { value = draft; self.draft = nil }
      })
      .accessibilityLabel(title)
      .accessibilityIdentifier(identifier ?? "portrait.adjustment.\(title)")
      Text(String(format: "%.*f%@", precision, draft ?? value, unit)).monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 46, alignment: .trailing)
    }
    .font(.caption)
    .frame(minHeight: 22)
  }
}
