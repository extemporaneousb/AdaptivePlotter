import AppKit
import PortraitCore
import SwiftUI

struct PortraitStudioReviewView: View {
  @Bindable var model: PortraitStudioReviewModel
  var exportDataset: () -> Void = {}
  var isExporting = false
  @State private var dimension: PortraitReviewDimension = .overall

  private let dimensions: [(PortraitReviewDimension, String)] = [
    (.overall, "Overall preference"), (.likeness, "Likeness"),
    (.expression, "Expression"), (.structure, "Structure"), (.tone, "Tone"),
    (.clutter, "Clutter"), (.materialFeasibility, "Material feasibility")
  ]
  private let choices: [(PortraitReviewChoice, String)] = [
    (.a, "A"), (.b, "B"), (.tie, "Tie"), (.neither, "Neither"), (.skip, "Skip")
  ]

  var body: some View {
    HSplitView {
      VStack(alignment: .leading) {
        Text("Comparisons").font(.headline)
        Button("Export Dataset", systemImage: "square.and.arrow.up", action: exportDataset)
          .help("Export exact retained results, jobs and human ratings to a new folder. Undeclared split assignments remain unassigned.")
          .disabled(model.isLoading || isExporting)
        List {
          ForEach(model.comparisons, id: \.id) { comparison in
            Button { Task { await model.select(comparison.id) } } label: {
              VStack(alignment: .leading) {
                Text(comparison.createdAt, style: .date)
                Text(comparison.id.uuidString.prefix(8)).font(.caption).foregroundStyle(.secondary)
              }
            }.buttonStyle(.plain)
          }
          if model.hasMore {
            Button("More Comparisons") { Task { await model.loadMore() } }
          }
        }
        if model.isLoading { ProgressView().controlSize(.small) }
      }.padding(8).frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
      if let comparison = model.comparison, let a = model.a, let b = model.b,
        let displayA = model.displayA, let displayB = model.displayB {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
              Text("Original photo").font(.headline)
              asset(a.source.bytes).frame(width: 200, height: 180)
            }
            VStack(alignment: .leading, spacing: 8) {
              Text("Review immutable drawings").font(.title2)
              Text("A/B order is randomized and retained. Choose overall preference first; record other dimensions only when you judge them.")
                .font(.caption).foregroundStyle(.secondary)
              TextField("Reviewer (optional)", text: $model.reviewerID)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
              Text("Blank reviewer identity remains unknown. Age is not rated without ground truth.")
                .font(.caption).foregroundStyle(.secondary)
              Text("Rubric \(comparison.rubricVersion)").font(.caption.monospaced())
              Text("Display field \(comparison.displayMaterial.widthMM, specifier: "%.1f") × \(comparison.displayMaterial.heightMM, specifier: "%.1f") mm · nominal display pen \(comparison.displayMaterial.nominalLineWidthMM, specifier: "%.2f") mm")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          HStack(spacing: 16) {
            result(a, display: displayA, reference: comparison.a, title: "A")
            result(b, display: displayB, reference: comparison.b, title: "B")
          }.frame(maxHeight: .infinity)
          HStack {
            Picker("Judgment", selection: $dimension) {
              ForEach(dimensions, id: \.0) { value, title in Text(title).tag(value) }
            }.frame(maxWidth: 270)
            ForEach(choices, id: \.0.rawValue) { choice, title in
              Button(title) { Task { await model.rate(choice, dimension: dimension) } }
                .disabled(model.isLoading || isExporting || (dimension != .overall &&
                  (model.label?.choices[.overall] == nil || model.label?.choices[.overall] == .skip)))
                .accessibilityIdentifier("portrait.review.\(choice.rawValue)")
            }
          }
          if let label = model.label {
            Text("Recorded \(dimensions.first(where: { $0.0 == dimension })?.1 ?? "judgment"): \(label.choices[dimension]?.rawValue ?? "unassessed")")
              .font(.caption).foregroundStyle(.secondary)
          } else { Text("No human rating recorded.").font(.caption).foregroundStyle(.secondary) }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityIdentifier("portrait.review.originalVisible")
      } else {
        ContentUnavailableView("Choose Two Retained Drawings", systemImage: "rectangle.split.2x1",
          description: Text("In Library, select a native or imported drawing and choose Use as First Drawing. Select another drawing from the same exact source and choose Compare with First Drawing."))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task { await model.reload() }
    .onChange(of: model.comparison?.id) { _, _ in dimension = .overall }
    .alert("Review needs attention", isPresented: Binding(get: { model.error != nil },
      set: { if !$0 { model.error = nil } })) {
      Button("OK", role: .cancel) { model.error = nil }
    } message: { Text(model.error ?? "") }
  }

  private func result(_ package: DrawingPackage, display: DrawingPackageAsset,
    reference: PortraitReviewResultReference, title: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.title2)
      asset(display.bytes).frame(maxWidth: .infinity, maxHeight: .infinity)
      Text("\(package.program.strokes.count) strokes · \(package.program.strokes.reduce(0) { $0 + $1.path.points.count }) points")
        .font(.caption).foregroundStyle(.secondary)
      Text("Reference field \(reference.material.widthMM, specifier: "%.1f") × \(reference.material.heightMM, specifier: "%.1f") mm · nominal pen \(reference.nominalLineWidthsMM.map { String(format: "%.2f", $0) }.joined(separator: ", ")) mm")
        .font(.caption).foregroundStyle(.secondary)
      Text("Pen provenance: \(reference.material.provenance ?? "unknown") · physical material qualification unverified")
        .font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private func asset(_ bytes: Data) -> some View {
    if let image = NSImage(data: bytes) {
      Image(nsImage: image).resizable().scaledToFit()
    } else { ContentUnavailableView("Retained Image Unavailable", systemImage: "photo") }
  }
}
