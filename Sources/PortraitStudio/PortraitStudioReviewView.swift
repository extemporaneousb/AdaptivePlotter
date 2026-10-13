import AppKit
import PortraitCore
import SwiftUI

struct PortraitStudioReviewView: View {
  @Bindable var model: PortraitStudioReviewModel
  var exportDataset: () -> Void = {}
  var isExporting = false
  @State private var showsDetails = false
  @State private var dimension: PortraitReviewDimension = .likeness

  private let dimensions: [(PortraitReviewDimension, String)] = [
    (.likeness, "Likeness"), (.expression, "Expression"), (.structure, "Structure"),
    (.tone, "Tone"), (.clutter, "Clutter"), (.materialFeasibility, "Material feasibility")
  ]
  private let choices: [(PortraitReviewChoice, String)] = [
    (.a, "A"), (.b, "B"), (.tie, "Tie"), (.neither, "Neither"), (.skip, "Skip")
  ]

  var body: some View {
    HSplitView {
      comparisonList
      if let comparison = model.comparison, let a = model.a, let b = model.b,
        let displayA = model.displayA, let displayB = model.displayB {
        VStack(alignment: .leading, spacing: 10) {
          navigation
          HStack(alignment: .top, spacing: 12) {
            imagePane(a.source.bytes, title: "Original", identifier: "portrait.review.original")
              .frame(minWidth: 150, idealWidth: 200, maxWidth: 240)
            imagePane(displayA.bytes, title: "A", identifier: "portrait.review.displayA")
            imagePane(displayB.bytes, title: "B", identifier: "portrait.review.displayB")
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("portrait.review.originalVisible")
          HStack(spacing: 8) {
            Text("Overall").font(.headline)
            scoreButtons(dimension: .overall, showsKeys: true)
            Spacer(minLength: 0)
          }.accessibilityIdentifier("portrait.review.overallScores")
          if model.reachedEnd {
            Label(model.allLoadedReviewed ? "Review complete" : "Last comparison", systemImage: "checkmark.circle")
              .font(.callout).foregroundStyle(.secondary)
              .accessibilityIdentifier("portrait.review.completion")
          }
          DisclosureGroup("Details", isExpanded: $showsDetails) {
            ScrollView {
              details(comparison, a: a, b: b)
                .padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 175)
          }.accessibilityIdentifier("portrait.review.details")
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView("No Comparisons", systemImage: "rectangle.split.2x1",
          description: Text("Choose two drawings from the same source in Library."))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background {
      PortraitStudioReviewKeyRouter(enabled: !model.isLoading && !isExporting) { key in
        switch key {
        case .previous: return model.previous()
        case .next: return model.next()
        case .score(let choice): return model.score(choice)
        }
      }
    }
    .task { await model.reload() }
    .onChange(of: model.comparison?.id) { _, _ in dimension = .likeness }
    .alert("Review needs attention", isPresented: Binding(get: { model.error != nil },
      set: { if !$0 { model.error = nil } })) {
      Button("OK", role: .cancel) { model.error = nil }
    } message: { Text(model.error ?? "") }
  }

  private var comparisonList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Review").font(.headline)
      Text("\(model.reviewedCount) reviewed · \(model.skippedCount) skipped\n\(model.unratedCount) unrated\(model.hasMore ? " · loaded" : "")")
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityIdentifier("portrait.review.progress")
      List(selection: Binding<UUID?>(get: { model.comparison?.id }, set: { id in
        if let id { model.selectComparison(id) }
      })) {
        ForEach(Array(model.comparisons.enumerated()), id: \.element.id) { index, comparison in
          HStack {
            Text("\(index + 1)").monospacedDigit()
            Spacer()
            Image(systemName: statusIcon(model.status(for: comparison.id)))
              .accessibilityLabel(model.status(for: comparison.id).rawValue.capitalized)
          }.tag(comparison.id)
            .accessibilityIdentifier("portrait.review.row.\(comparison.id.uuidString)")
        }
        if model.hasMore {
          Button("Load More") { model.loadNextPage() }.disabled(model.isLoading)
        }
      }.disabled(model.isLoading || isExporting)
      Button("Export", systemImage: "square.and.arrow.up", action: exportDataset)
        .help("Export exact results and explicit ratings to a new folder.")
        .disabled(model.isLoading || isExporting)
        .accessibilityIdentifier("portrait.review.export")
    }.padding(8).frame(minWidth: 140, idealWidth: 160, maxWidth: 200)
  }

  private var navigation: some View {
    HStack(spacing: 8) {
      Button("Previous", systemImage: "chevron.left") { model.previous() }
        .disabled(!model.canGoPrevious || isExporting)
        .help("Previous comparison (Left Arrow).")
        .accessibilityIdentifier("portrait.review.previous")
      Text("\((model.currentIndex ?? 0) + 1) / \(model.comparisons.count)\(model.hasMore ? "+" : "")")
        .font(.callout.monospacedDigit())
        .accessibilityIdentifier("portrait.review.position")
      Button("Next", systemImage: "chevron.right") { model.next() }
        .disabled(!model.canGoNext || isExporting)
        .help("Next comparison (Right Arrow). Browsing does not record a rating.")
        .accessibilityIdentifier("portrait.review.next")
      Spacer()
      if model.isLoading { ProgressView().controlSize(.small) }
    }
  }

  private func scoreButtons(dimension: PortraitReviewDimension, showsKeys: Bool) -> some View {
    ForEach(Array(choices.enumerated()), id: \.element.0.rawValue) { index, pair in
      let selected = model.label?.choices[dimension] == pair.0
      Button {
        model.score(pair.0, dimension: dimension)
      } label: {
        HStack(spacing: 4) {
          if selected { Image(systemName: "checkmark") }
          Text(pair.1)
          if showsKeys { Text("\(index + 1)").font(.caption).foregroundStyle(.secondary) }
        }
      }
      .tint(selected ? Color.accentColor : nil)
      .disabled(!model.canScore || isExporting || (dimension != .overall &&
        (model.label?.choices[.overall] == nil || model.label?.choices[.overall] == .skip)))
      .accessibilityLabel("\(pair.1)\(selected ? ", recorded" : "")")
      .accessibilityIdentifier(dimension == .overall ? "portrait.review.\(pair.0.rawValue)" : "portrait.review.dimension.\(pair.0.rawValue)")
    }
  }

  private func details(_ comparison: PortraitReviewComparison, a: DrawingPackage, b: DrawingPackage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Reviewer (optional)", text: $model.reviewerID)
          .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
          .accessibilityIdentifier("portrait.review.reviewer")
        Text("Rubric \(comparison.rubricVersion)").font(.caption.monospaced())
      }
      HStack {
        Picker("Optional judgment", selection: $dimension) {
          ForEach(dimensions, id: \.0) { value, title in Text(title).tag(value) }
        }.frame(maxWidth: 240).accessibilityIdentifier("portrait.review.dimension")
        scoreButtons(dimension: dimension, showsKeys: false)
      }
      Text("Display \(comparison.displayMaterial.widthMM, specifier: "%.1f") × \(comparison.displayMaterial.heightMM, specifier: "%.1f") mm · \(comparison.displayMaterial.nominalLineWidthMM, specifier: "%.2f") mm pen")
        .font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 16) {
        resultDetails(a, reference: comparison.a, title: "A")
        resultDetails(b, reference: comparison.b, title: "B")
      }
      Text("A/B order is retained. Unjudged dimensions and blank reviewer stay unknown. Physical material qualification is unverified.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func resultDetails(_ package: DrawingPackage, reference: PortraitReviewResultReference, title: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("\(title): \(package.program.strokes.count) strokes · \(package.program.strokes.reduce(0) { $0 + $1.path.points.count }) points")
      Text("Field \(reference.material.widthMM, specifier: "%.1f") × \(reference.material.heightMM, specifier: "%.1f") mm · pen \(reference.nominalLineWidthsMM.map { String(format: "%.2f", $0) }.joined(separator: ", ")) mm")
      Text("Pen provenance: \(reference.material.provenance ?? "unknown")")
    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
  }

  private func imagePane(_ bytes: Data, title: String, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.headline)
      if let image = NSImage(data: bytes) {
        Image(nsImage: image).resizable().scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else { ContentUnavailableView("Image Unavailable", systemImage: "photo") }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier(identifier)
  }

  private func statusIcon(_ status: PortraitStudioReviewModel.ReviewStatus) -> String {
    switch status { case .unrated: "circle"; case .reviewed: "checkmark.circle.fill"; case .skipped: "forward.circle" }
  }
}
