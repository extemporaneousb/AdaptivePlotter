import CoreGraphics
import Foundation
import PlotterModel
import PlotterRuntime
import SwiftUI

/// Exact immutable images, geometry and applicability offered for an operator
/// visibility assertion. Live camera updates cannot replace these inputs.
struct DrawingMaterialInspection: Identifiable {
  let id: UUID
  let profile: DrawingMaterialProfileRevision
  let applicability: DrawingMaterialApplicability
  let registration: TipCameraRegistration
  let baseline: SamePoseFrameSample?
  let result: SamePoseFrameSample
  let paths: [Polyline<MachineSpace>]

  init(id: UUID = UUID(), profile: DrawingMaterialProfileRevision,
    applicability: DrawingMaterialApplicability, registration: TipCameraRegistration,
    baseline: SamePoseFrameSample?, result: SamePoseFrameSample,
    paths: [Polyline<MachineSpace>]) {
    self.id = id
    self.profile = profile
    self.applicability = applicability
    self.registration = registration
    self.baseline = baseline
    self.result = result
    self.paths = paths
  }
}

struct DrawingMaterialInspectionView: View {
  let inspection: DrawingMaterialInspection
  let confirm: () async -> String?
  let cancel: () -> Void
  private let baselineImage: CGImage?
  private let resultImage: CGImage?
  @State private var showOriginalPixels = false
  @State private var conditionsConfirmed = false
  @State private var inProgress = false
  @State private var completed = false
  @State private var status: String?

  init(inspection: DrawingMaterialInspection, confirm: @escaping () async -> String?,
    cancel: @escaping () -> Void) {
    self.inspection = inspection
    self.confirm = confirm
    self.cancel = cancel
    // Reuse the production preview converter; conversion occurs once for the
    // frozen inspection rather than on each asynchronous status update.
    baselineImage = inspection.baseline.flatMap { FrameImageFactory.image(from: $0.frame) }
    resultImage = FrameImageFactory.image(from: inspection.result.frame)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Inspect Material Measurement Images").font(.title2)
      Text("\(inspection.profile.name) · revision \(inspection.profile.revision) · \(inspection.paths.count) measured paths")
        .font(.subheadline)
      StudioHelpButton("Inspect measurement images", text: "Inspect every mark and the paper on both sides in these exact images. No pen, armature, hand or other object may obscure them. Confirm the material and paper settings before measuring. This action sends no motion commands. " + (inspection.baseline == nil
        ? "A single image estimates width against local paper contrast; deposition time is unknown."
        : "The baseline and result were captured at the same controller pose."))
      Toggle("Material and paper settings match", isOn: $conditionsConfirmed)
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("drawing.material.inspection.confirmConditions")
      Toggle("Show original pixels", isOn: $showOriginalPixels)
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("drawing.material.inspection.originalPixels")
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let baseline = inspection.baseline {
            imagePanel(title: "Baseline", sample: baseline, image: baselineImage)
          }
          imagePanel(title: inspection.baseline == nil ? "Existing marks" : "Result",
            sample: inspection.result, image: resultImage)
        }
      }
      .frame(minHeight: 240)
      if let status {
        Text(status).font(.callout).textSelection(.enabled)
          .accessibilityIdentifier("drawing.material.inspection.status")
      }
      HStack(alignment: .center, spacing: 12) {
        Button("Cancel", action: cancel)
          .keyboardShortcut(.cancelAction)
          .disabled(inProgress)
          .accessibilityIdentifier("drawing.material.inspection.cancel")
        Spacer(minLength: 0)
        if inProgress { ProgressView().controlSize(.small) }
        Button {
          inProgress = true
          status = nil
          Task { @MainActor in
            let error = await confirm()
            inProgress = false
            completed = error == nil
            status = error ?? "Measurement completed for these exact images."
          }
        } label: {
          Text("Confirm Visible Marks & Measure")
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!conditionsConfirmed || inProgress || completed || resultImage == nil
          || (inspection.baseline != nil && baselineImage == nil))
        .accessibilityIdentifier("drawing.material.inspection.confirmVisibility")
      }
    }
    .padding(20)
    .frame(minWidth: 640, idealWidth: 840, maxWidth: 1000,
      minHeight: 520, idealHeight: 740, maxHeight: 900)
  }

  @ViewBuilder
  private func imagePanel(title: String, sample: SamePoseFrameSample, image: CGImage?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline)
      StudioHelpButton("Image identity", text: "Frame \(sample.frame.id.rawValue), \(sample.frame.width) × \(sample.frame.height), captured \(sample.frame.captureNanoseconds) ns")
      if let image {
        if showOriginalPixels {
          ScrollView([.horizontal, .vertical]) {
            Image(decorative: image, scale: 1)
              .resizable().interpolation(.none)
              .frame(width: CGFloat(image.width), height: CGFloat(image.height))
          }
          .frame(height: min(420, CGFloat(image.height)))
        } else {
          Image(decorative: image, scale: 1)
            .resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 420)
        }
      } else {
        VStack {
          ContentUnavailableView("Image unavailable", systemImage: "photo")
          StudioHelpButton("Image unavailable", text: "The frozen image could not be displayed. Visibility cannot be confirmed.")
        }
      }
    }
  }
}
