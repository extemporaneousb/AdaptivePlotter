import SwiftUI

struct PortraitRenderControls: View {
  @Bindable var model: PortraitStudioModel
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Style", selection: Binding(get: { model.style }, set: {
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.style")
        model.style = $0
      })) {
        ForEach(PortraitStyle.allCases) { Text($0 == .contours ? "Tonal contours" : $0.rawValue).tag($0) }
      }.accessibilityIdentifier("portrait.style")
      ViewThatFits {
        HStack { presets }
        VStack(alignment: .leading) { presets }
      }
      DisclosureGroup("Line and shading controls") {
        VStack(alignment: .leading, spacing: 8) {
          if model.style != .hatch && model.style != .crosshatch {
          PortraitAdjustmentSlider("Minimum contour", value: $model.vectorOptions.minimumContourLength,
            range: 0...40, step: 0.5, unit: "px")
          PortraitAdjustmentSlider("Simplification", value: $model.vectorOptions.simplificationTolerance,
            range: 0...3, step: 0.05, unit: "px")
          }
          PortraitAdjustmentSlider("Smoothing", value: $model.vectorOptions.smoothing,
            range: 0...4, step: 0.1, unit: "px")
          if model.style == .contours {
            Stepper("Tonal levels: \(model.vectorOptions.contourLevels)",
              value: $model.vectorOptions.contourLevels, in: 1...12)
          }
          if model.style == .hatch || model.style == .crosshatch || model.style == .sketchHatch {
            Stepper("Hatch spacing: \(model.vectorOptions.hatchSpacing) px",
              value: $model.vectorOptions.hatchSpacing, in: 1...16)
            PortraitAdjustmentSlider("Hatch angle", value: $model.vectorOptions.hatchAngleDegrees,
              range: -90...90, step: 5, unit: "°", precision: 0)
          }
          PortraitAdjustmentSlider("Tonal strength", value: $model.vectorOptions.tonalStrength,
            range: 0.4...2, step: 0.05, unit: "×")
          if model.style == .sketch || model.style == .sketchHatch {
            PortraitAdjustmentSlider("Edge threshold", value: $model.vectorOptions.sketchThreshold,
              range: 0.002...0.08, step: 0.002, unit: "", precision: 3)
          }
          Text("Pixels refer to the analyzed image. Larger spacing, fewer levels and longer minimum lines reduce detail and ink density.")
            .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 6)
      }
      DisclosureGroup("Face framing") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Crop to face", isOn: $model.options.cropToFace)
          if model.options.cropToFace {
            PortraitAdjustmentSlider("Head margin", value: $model.options.faceCropMargin,
              range: 0.05...0.8, step: 0.05, unit: "×")
            Text("Smaller margins fill the drawing with the head; larger margins include hair and shoulders.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Toggle("Remove background", isOn: $model.options.removeBackground)
          Toggle("Semantic Big Head", isOn: Binding(get: {
            model.vectorOptions.semanticHead != nil
          }, set: { enabled in
            model.vectorOptions.semanticHead = enabled ? PortraitSemanticHeadParameters() : nil
            model.vectorOptions.headScale = 1
          })).accessibilityIdentifier("portrait.semanticHead")
          if model.vectorOptions.semanticHead != nil {
            PortraitAdjustmentSlider("Forehead width", value: semanticBinding(\.foreheadWidth),
              range: 0...0.6, step: 0.02, unit: "")
            PortraitAdjustmentSlider("Forehead height", value: semanticBinding(\.foreheadHeight),
              range: 0...0.6, step: 0.02, unit: "")
            PortraitAdjustmentSlider("Eye emphasis", value: semanticBinding(\.eyeScale),
              range: 0...0.6, step: 0.02, unit: "")
            PortraitAdjustmentSlider("Upper lateral width", value: semanticBinding(\.lateralScale),
              range: 0...0.6, step: 0.02, unit: "")
          }
          Text("Uses recorded facial landmarks and pose; protects the mouth and chin. Forehead anchors are estimated. Ears are not detected. Unsupported analysis leaves the shape unchanged.")
            .font(.caption).foregroundStyle(.secondary)
          if let manifest = model.selectedCandidate?.warpManifest {
            Text(manifest.summary).font(.caption).foregroundStyle(.secondary)
          }
          if model.vectorOptions.semanticHead == nil && model.vectorOptions.headScale > 1 {
            Text("Archived head transform. Enable Semantic Big Head to generate a new version.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(.top, 6)
      }
    }
  }

  private func semanticBinding(_ keyPath: WritableKeyPath<PortraitSemanticHeadParameters, Double>) -> Binding<Double> {
    Binding(get: { (model.vectorOptions.semanticHead ?? PortraitSemanticHeadParameters())[keyPath: keyPath] },
      set: { value in
        var parameters = model.vectorOptions.semanticHead ?? PortraitSemanticHeadParameters()
        parameters[keyPath: keyPath] = value
        model.vectorOptions.semanticHead = parameters
      })
  }

  @ViewBuilder private var presets: some View {
    Text("Detail").font(.caption).foregroundStyle(.secondary)
    ForEach(PortraitVectorPreset.allCases, id: \.self) { preset in
      Button(preset.rawValue) {
        var options = preset.options
        options.headScale = model.vectorOptions.headScale
        options.semanticHead = model.vectorOptions.semanticHead
        model.vectorOptions = options
      }
        .accessibilityIdentifier("portrait.preset.\(preset.rawValue)")
    }
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
  @State private var draft: Double?
  @State private var isEditing = false

  init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
       unit: String, precision: Int = 2) {
    self.title = title
    _value = value
    self.range = range
    self.step = step
    self.unit = unit
    self.precision = precision
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title)
        Spacer()
        Text(String(format: "%.*f %@", precision, draft ?? value, unit)).monospacedDigit()
          .foregroundStyle(.secondary)
      }.font(.caption)
      Slider(value: Binding(get: { draft ?? value }, set: { proposed in
        let rounded = min(range.upperBound, max(range.lowerBound, (proposed/step).rounded()*step))
        draft = rounded
        if !isEditing { value = rounded; draft = nil }
      }), in: range, onEditingChanged: { editing in
        isEditing = editing
        if !editing, let draft { value = draft; self.draft = nil }
      })
      .accessibilityLabel(title)
    }
  }
}
