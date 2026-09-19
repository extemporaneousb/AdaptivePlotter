import SwiftUI

/// Framing and algorithm tuning share the drawing's visible editing surface.
struct PortraitRenderControls: View {
  @Bindable var model: PortraitStudioModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
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
      Divider().padding(.vertical, 2)
      HStack {
        Text(model.style.rawValue).font(.headline)
        Spacer()
        StudioHelpButton("Style adjustments", text: "These parameters change the selected rendering algorithm. Pixels refer to the analyzed image. Longer minimum contours, larger hatch spacing and fewer tonal levels reduce detail and ink density. Detail presets set these parameters together; they do not change the calibrated pen width.")
      }
      HStack(spacing: 5) {
        Text("Detail").font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        ForEach(PortraitVectorPreset.allCases, id: \.self) { preset in
          Button(preset == .broadMarker ? "Coarse" : preset.rawValue) {
            var options = preset.options
            options.materialContext = model.vectorOptions.materialContext
            model.vectorOptions = options
          }
          .accessibilityIdentifier("portrait.preset.\(preset.rawValue)")
        }
      }.controlSize(.small)
      if model.style != .hatch && model.style != .crosshatch {
        PortraitAdjustmentSlider("Min. contour", value: $model.vectorOptions.minimumContourLength,
          range: 0...40, step: 0.5, unit: "px", precision: 1)
        PortraitAdjustmentSlider("Simplification", value: $model.vectorOptions.simplificationTolerance,
          range: 0...3, step: 0.05, unit: "px")
      }
      PortraitAdjustmentSlider("Smoothing", value: $model.vectorOptions.smoothing,
        range: 0...4, step: 0.1, unit: "px", precision: 1)
      if model.style == .contours {
        Stepper("Tonal levels: \(model.vectorOptions.contourLevels)",
          value: $model.vectorOptions.contourLevels, in: 1...12)
          .font(.caption)
      }
      if model.style == .hatch || model.style == .crosshatch || model.style == .sketchHatch {
        Stepper("Hatch spacing: \(model.vectorOptions.hatchSpacing) px",
          value: $model.vectorOptions.hatchSpacing, in: 1...16)
          .font(.caption)
        PortraitAdjustmentSlider("Hatch angle", value: $model.vectorOptions.hatchAngleDegrees,
          range: -90...90, step: 5, unit: "°", precision: 0)
      }
      PortraitAdjustmentSlider("Tonal strength", value: $model.vectorOptions.tonalStrength,
        range: 0.4...2, step: 0.05, unit: "×")
      if model.style == .sketch || model.style == .sketchHatch {
        PortraitAdjustmentSlider("Edge threshold", value: $model.vectorOptions.sketchThreshold,
          range: 0.002...0.08, step: 0.002, unit: "", precision: 3)
      }
    }
    .controlSize(.small)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.adjustments")
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
      Text(String(format: "%.*f%@", precision, draft ?? value, unit)).monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 46, alignment: .trailing)
    }
    .font(.caption)
    .frame(minHeight: 22)
  }
}
