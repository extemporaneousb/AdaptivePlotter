import PlotterModel
import SwiftUI

/// Framing is shared; each drawing style edits its native renderer parameters.
struct PortraitRenderControls: View {
  @Bindable var model: PortraitStudioModel

  let strokeStyle: PlotterModel.StrokeStyle
  @Binding var showsAdvanced: Bool
  @State private var savingStyle = false
  @State private var styleName = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
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
      HStack {
        Text(model.style.rawValue).font(.headline)
        Spacer()
        StudioHelpButton("Style parameters", text: styleHelp)
      }
      if !model.canEditNativeParameters {
        Text("Rendering saved recipe…")
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("portrait.parametersPending")
      }
      nativeControls
        .disabled(!model.canEditNativeParameters)
      HStack(spacing: 5) {
        ForEach(PortraitVectorPreset.allCases, id: \.self) { preset in
          Button(preset == .broadMarker ? "Coarse" : preset.rawValue) {
            WorkbenchRequestTelemetry.nativeActionHandled("portrait.preset.\(preset.rawValue)")
            model.applyDetailPreset(preset)
          }
          .disabled(!model.canEditNativeParameters)
          .accessibilityIdentifier("portrait.preset.\(preset.rawValue)")
        }
        Spacer(minLength: 0)
        Button("Reset") { model.resetStyle(model.style, strokeStyle: strokeStyle) }
          .help("Reset this style's parameters, keeping photo framing and material")
          .accessibilityIdentifier("portrait.resetParameters")
      }
      if model.style == .flowEdges {
        flowAdvancedControls
          .disabled(!model.canEditNativeParameters)
      }
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
    }
    .controlSize(.small)
    .disabled(model.isCapturing)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.adjustments")
  }

  @ViewBuilder private var nativeControls: some View {
    if model.style == .contours {
      Stepper("Tonal levels: \(model.nativeVectorOptions.contourLevels)",
        value: nativeBinding(\.contourLevels), in: 1...12)
        .font(.caption)
        .accessibilityIdentifier("portrait.contourLevels")
    }
    if model.style == .flowEdges {
      Stepper("Flow spacing: \(model.nativeVectorOptions.hatchSpacing) px",
        value: nativeBinding(\.hatchSpacing), in: 3...16)
        .font(.caption)
        .accessibilityIdentifier("portrait.flowSpacing")
    }
    if model.style != .hatch && model.style != .crosshatch {
      PortraitAdjustmentSlider(model.style == .flowEdges ? "Min. line" : "Min. contour",
        value: nativeBinding(\.minimumContourLength), range: 0...40, step: 0.5, unit: "px", precision: 1,
        identifier: "portrait.minimumLine")
      if model.style != .flowEdges {
        PortraitAdjustmentSlider("Simplification", value: nativeBinding(\.simplificationTolerance),
          range: 0...3, step: 0.05, unit: "px", identifier: "portrait.simplification")
      }
    }
    PortraitAdjustmentSlider(model.style == .flowEdges ? "Coherence" : "Smoothing",
      value: nativeBinding(\.smoothing), range: 0...4, step: 0.1,
      unit: model.style == .flowEdges ? "" : "px", precision: 1,
      identifier: model.style == .flowEdges ? "portrait.flowCoherence" : "portrait.smoothing")
    PortraitAdjustmentSlider(model.style == .flowEdges ? "Tone density" : "Tonal strength",
      value: nativeBinding(\.tonalStrength), range: 0.4...2, step: 0.05, unit: "×",
      identifier: model.style == .flowEdges ? "portrait.flowToneDensity" : "portrait.tonalStrength")
    if model.style == .flowEdges || model.style == .sketch || model.style == .sketchHatch {
      PortraitAdjustmentSlider("Edge threshold", value: nativeBinding(\.sketchThreshold),
        range: 0.002...0.08, step: 0.002, unit: "", precision: 3,
        identifier: "portrait.edgeThreshold")
    }
  }

  private var flowAdvancedControls: some View {
    DisclosureGroup("Flow Edge options", isExpanded: $showsAdvanced) {
      VStack(alignment: .leading, spacing: 4) {
        Picker("Line form", selection: Binding(
          get: { FlowLineForm(value: model.nativeVectorOptions.flowRectilinearity ?? 0) },
          set: { form in model.editNativeVectorOptions { $0.flowRectilinearity = form.value } })) {
          ForEach(FlowLineForm.allCases, id: \.self) { form in Text(form.rawValue).tag(form) }
        }
        .accessibilityIdentifier("portrait.flowLineForm")
        PortraitAdjustmentSlider("Tone support", value: flowBinding(\.flowSupport),
          range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSupport")
        PortraitAdjustmentSlider("Persistence", value: flowBinding(\.flowStructureSupport),
          range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowStructureSupport")
        PortraitAdjustmentSlider("Evidence scale", value: flowBinding(\.flowSupportScale),
          range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSupportScale")
          .disabled((model.nativeVectorOptions.flowSupport ?? 0) == 0
            && (model.nativeVectorOptions.flowStructureSupport ?? 0) == 0)
        PortraitAdjustmentSlider("Irregularity", value: flowBinding(\.flowSeedIrregularity),
          range: 0...1, step: 0.05, unit: "", identifier: "portrait.flowSeedIrregularity")
      }.padding(.top, 4)
    }
    .help("Line form changes shading direction. Support controls determine which image evidence sustains shading and feature curves. Zero retains the original behavior.")
    .accessibilityIdentifier("portrait.adjustmentsDisclosure")
  }

  private var styleHelp: String {
    let description: String
    switch model.style {
    case .flowEdges:
      description = "Flow Edge traces feature curves and fills shadows with directed lines. Flow spacing sets the distance between shading lines; tone density changes shadow coverage; edge threshold filters feature curves; coherence aligns nearby line directions. Minimum line length removes short curves. The secondary Flow Edge options control line form and image support. Presets keep those choices."
    case .contours:
      description = "Contour traces tonal boundaries. Tonal levels set the number of brightness thresholds; minimum contour length removes short curves; simplification removes small turns; smoothing softens the analyzed image; tonal strength adjusts its luminance curve."
    case .sketch, .sketchHatch:
      description = "Sketch traces structural edges using a difference of Gaussian blurs. Edge threshold filters weak responses; minimum contour length removes short curves; simplification removes small turns; smoothing and tonal strength adjust the analyzed image. Sketch + hatch adds shadow lines."
    case .hatch, .crosshatch:
      description = "Hatch fills darker image areas with straight lines. Crosshatch adds lines in a second direction. Smoothing and tonal strength adjust the analyzed image used to choose shadow coverage."
    }
    return description + " Spatial values are in analyzed-image pixels. Material adaptation can raise minimum spacing and line length at the placed size. Presets do not change pen width."
  }

  private func nativeBinding<Value>(_ keyPath: WritableKeyPath<PortraitVectorOptions, Value>) -> Binding<Value> {
    Binding(get: { model.nativeVectorOptions[keyPath: keyPath] },
      set: { value in model.editNativeVectorOptions { $0[keyPath: keyPath] = value } })
  }

  private func flowBinding(_ keyPath: WritableKeyPath<PortraitVectorOptions, Double?>) -> Binding<Double> {
    Binding(get: { model.nativeVectorOptions[keyPath: keyPath] ?? 0 },
      set: { value in model.editNativeVectorOptions { $0[keyPath: keyPath] = PortraitVectorOptions.flowAmount(value) } })
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
        if !isEditing { commit(rounded); draft = nil }
      }), in: range, onEditingChanged: { editing in
        isEditing = editing
        if !editing, let draft { commit(draft); self.draft = nil }
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

  private func commit(_ value: Double) {
    WorkbenchRequestTelemetry.nativeActionHandled(identifier ?? "portrait.adjustment.\(title)")
    self.value = value
  }
}
