import PlotterRuntime
import SwiftUI

/// Physical images are an explicit gallery surface, separate from vector previews.
struct DrawingStudioPhysicalGallery: View {
  let application: PlotterApplicationRuntime
  @State private var selectedRecord: DrawingRunEvidenceRecord?
  private var records: [DrawingRunEvidenceRecord] {
    guard let candidate = application.portraitStudio.selectedCandidate else { return [] }
    return application.physicalAttempts(candidateID: candidate.id)
  }
  var body: some View {
    if !records.isEmpty {
      DisclosureGroup("Physical drawings · \(records.count) attempts") {
        ForEach(records, id: \.recordID) { record in
          Button {
            selectedRecord = record
          } label: {
            VStack(alignment: .leading) {
              Text("Attempt \(String(record.runID.description.prefix(8))) · \(physicalExecutionSummary(record.executionDisposition))")
              Text("\(record.attemptEvidence?.terminalFrames.count ?? 0) available terminal images")
                .font(.caption).foregroundStyle(.secondary)
            }
          }.accessibilityIdentifier("portrait.physicalAttempt.\(record.runID)")
        }
      }
      .sheet(isPresented: Binding(get: { selectedRecord != nil }, set: { if !$0 { selectedRecord = nil } })) {
        if let record = selectedRecord {
          DrawingStudioPhysicalImages(application: application, record: record,
            close: { selectedRecord = nil })
        }
      }
    }
  }
}

private struct DrawingStudioPhysicalImages: View {
  let application: PlotterApplicationRuntime
  let record: DrawingRunEvidenceRecord
  let close: () -> Void
  @State private var images: [CGImage] = []
  @State private var status: String?
  @State private var loading = true
  @State private var originalPixels = false
  private var baselineCount: Int { record.attemptEvidence?.baselines.count ?? 0 }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Physical drawing · \(String(record.runID.description.prefix(8)))").font(.title2)
        Spacer()
        Button("Done", action: close)
      }
      Text(physicalExecutionSummary(record.executionDisposition)).font(.subheadline)
      Text(record.attemptEvidence?.missingCoverageReason ?? "Coverage is retained per pixel; raw images do not prove unseen regions are clear.")
        .font(.caption).foregroundStyle(.secondary)
      Toggle("Original image pixels", isOn: $originalPixels).toggleStyle(.checkbox)
      ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(images.enumerated()), id: \.offset) { index, image in
            VStack(alignment: .leading) {
              Text(index < baselineCount ? "Baseline \(index + 1)" : "Available terminal image \(index - baselineCount + 1)")
              Image(decorative: image, scale: 1).resizable()
                .frame(width: originalPixels ? CGFloat(image.width) : 680,
                  height: originalPixels ? CGFloat(image.height) : 680 * CGFloat(image.height) / CGFloat(image.width))
            }
          }
        }
      }
      if loading { ProgressView("Verifying original image assets") }
      HStack {
        Text("Physical realization")
        ForEach(1...5, id: \.self) { rating in
          Button("\(rating)") { status = application.ratePhysicalAttempt(record, rating: rating) ?? "Physical rating queued; screen ratings are unchanged." }
            .disabled(loading || images.count <= baselineCount)
            .accessibilityLabel("Rate physical drawing \(rating) of 5")
        }
      }
      PortraitArchiveStatus(collection: application.portraitStudio.sketches)
      if let status { Text(status).font(.caption).textSelection(.enabled) }
    }.padding(20).frame(minWidth: 760, minHeight: 640)
      .task(id: record.recordID) {
        do {
          let originals = try await application.physicalAttemptImages(record)
          guard !Task.isCancelled else { return }
          images = try originals.map { frame in
            guard let image = FrameImageFactory.image(from: frame.frame) else {
              throw DrawingRunEvidenceError.invalidMediaReference
            }
            return image
          }
        } catch { status = "Original images unavailable: \(error.localizedDescription)" }
        loading = false
      }
  }
}

private func physicalExecutionSummary(_ disposition: DrawingRunExecutionDisposition) -> String {
  switch disposition {
  case .completed: "Controller completed"
  case .refused(let reason): "Refused: " + reason
  case .cancelled(let reason): "Stopped: " + reason
  case .ambiguous(let reason): "Uncertain controller outcome: " + reason
  case .failed(let reason): "Failed: " + reason
  }
}
