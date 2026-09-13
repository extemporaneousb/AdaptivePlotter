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
      Text(inspection.baseline == nil
        ? "Existing ink: one frozen image, measured against local paper contrast. Deposition time and attempt attribution remain unknown."
        : "New ink: a frozen baseline and result captured at the same controller pose.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Inspect every measured mark and the paper on both sides. Confirm only when no pen, armature, hand or other object hides any part of those regions in either image. This action measures existing images and sends no motion commands.")
        .font(.callout)
      Text("Declared conditions: \(inspection.applicability.paperStock) · \(inspection.applicability.drawingFeedMMPerMinute) mm/min · pen actuation \(inspection.applicability.penActuationProfile.revision). The original drawing request is not recovered here.")
        .font(.caption).foregroundStyle(.secondary)
      Toggle("These marks were drawn with this material, paper and pen settings", isOn: $conditionsConfirmed)
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
      Text("If visibility is uncertain or a region is obscured, cancel. Deposited width remains unavailable without a valid visibility assertion for these exact images.")
        .font(.caption).foregroundStyle(.secondary)
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
          Text("All measured marks and both sides are unobstructed in these exact images")
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
      Text("Frame \(sample.frame.id.rawValue) · \(sample.frame.width) × \(sample.frame.height) · captured \(sample.frame.captureNanoseconds) ns")
        .font(.caption.monospaced()).textSelection(.enabled)
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
        ContentUnavailableView("Image unavailable", systemImage: "photo",
          description: Text("The frozen image could not be displayed. Visibility cannot be confirmed."))
      }
    }
  }
}
