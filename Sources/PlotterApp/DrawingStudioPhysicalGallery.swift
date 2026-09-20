import ImageIO
import PlotterModel
import PlotterRuntime
import SwiftUI

/// Browsing retained drawings does not change the working Studio selection or
/// the live run. Both drawing producers share the existing evidence archive.
struct DrawingReviewerView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  var showOnPlotter: ((PortraitCandidate) async -> String?)? = nil
  @State private var selection: DrawingReviewSelection?
  @State private var originalPixels = false
  @State private var busy = false
  @State private var failure: String?

  private var drawings: [PortraitSavedSketch] { Array(application.portraitStudio.sketches.sketches.reversed()) }
  private var results: [DrawingRunEvidenceRecord] { Array(application.drawingReviewRecords.reversed()) }
  private var selections: [DrawingReviewSelection] {
    results.map { .result($0.recordID) } + drawings.map { .drawing($0.id) }
  }
  private var candidate: PortraitCandidate? {
    switch selection {
    case .drawing(let id): return drawings.first { $0.id == id }?.candidate
    case .result:
      guard let id = record?.attemptEvidence?.intent.context.candidate?.candidateID else { return nil }
      return drawings.first { $0.id == id }?.candidate
    case nil: return nil
    }
  }
  private var record: DrawingRunEvidenceRecord? {
    guard case .result(let id) = selection else { return nil }
    return results.first { $0.recordID == id }
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Drawing Reviewer").font(.title2)
        StudioHelpButton("Drawing Reviewer", text: "Imaginations and Drawing results share this reviewer. Viewing an item does not replace the current Studio edit or change the plotter. Fit shows the whole image; 100% shows each original image pixel. Send to Drawing keeps the exact selected result and opens Drawing with it placed on the plotter video. Adjust placement there. Sending does not move the plotter; Draw starts execution.")
        Spacer()
        Picker("Image size", selection: $originalPixels) {
          Text("Fit").tag(false)
          Text("100%").tag(true)
        }.pickerStyle(.segmented).frame(width: 140)
        Button("Close", action: close).keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("drawing.reviewer.close")
      }
      HSplitView {
        List(selection: $selection) {
          if !results.isEmpty {
            Section("Drawing results") {
              ForEach(results, id: \.recordID) { result in
                HStack {
                  Image(systemName: "photo")
                  VStack(alignment: .leading, spacing: 2) {
                    Text(resultTitle(result))
                      .lineLimit(1)
                    Text(physicalExecutionLabel(result.executionDisposition))
                      .font(.caption).foregroundStyle(.secondary)
                  }
                }.tag(DrawingReviewSelection.result(result.recordID))
                  .accessibilityIdentifier("drawing.reviewResult.\(result.recordID)")
              }
            }
          }
          if !drawings.isEmpty {
            Section("Imaginations") {
              ForEach(drawings) { drawing in
                HStack {
                  PortraitPlaneProgramPreview(preview: referencePreview(drawing.program))
                    .frame(width: 46, height: 56)
                  Text(drawing.candidate.recipe.title).lineLimit(2)
                }.tag(DrawingReviewSelection.drawing(drawing.id))
                  .accessibilityIdentifier("drawing.reviewSaved.\(drawing.id)")
              }
            }
          }
        }.frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
          .accessibilityIdentifier("drawing.reviewer.items")
        Group {
          if let record {
            DrawingReviewResult(application: application, record: record, candidate: candidate,
              originalPixels: originalPixels)
              .id(record.recordID)
          } else if let candidate {
            HStack(spacing: 12) {
              reviewPanel("Source") {
                DrawingReviewSource(candidate: candidate, originalPixels: originalPixels)
                  .id(candidate.sourceSHA256)
              }
              reviewPanel("Imagination") {
                PortraitPlaneProgramPreview(preview: referencePreview(candidate.program))
              }
            }
          } else {
            if application.portraitStudio.sketches.persistenceState == .loading {
              ProgressView("Loading Imaginations…")
            } else {
              ContentUnavailableView("No Imaginations or Drawing results", systemImage: "rectangle.stack")
            }
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      HStack {
        if let record {
          Button("Delete Result", role: .destructive) { deleteResult(record) }
            .disabled(busy).accessibilityIdentifier("drawing.reviewer.deleteResult")
          StudioHelpButton("Delete Result", text: "Removes this result from the reviewer and future drawing assessment. Execution provenance, possible-ink and no-redraw facts, and original media shared with calibration or material measurements remain retained. Deletion does not declare the paper clear or permit the drawing to run again.")
        } else if let candidate {
          Menu("Delete", systemImage: "trash") {
            Button("Delete Imagination", role: .destructive) { deleteDrawing(candidate) }
            Button("Delete Source and Its Imaginations", role: .destructive) { deleteSource(candidate) }
          }.fixedSize().disabled(busy).accessibilityIdentifier("drawing.reviewer.deleteSaved")
          StudioHelpButton("Delete Imagination", text: "Delete Imagination removes this saved imagination and its ratings. Delete Source and Its Imaginations removes all saved imaginations from this source photo. Unreferenced portrait image assets are deleted. Drawing results and the current working Studio edit are separate.")
        }
        if let candidate, let showOnPlotter {
          Button("Send to Drawing", systemImage: "video") {
            busy = true
            Task { @MainActor in
              failure = await showOnPlotter(candidate)
              busy = false
              if failure == nil { close() }
            }
          }.disabled(busy).accessibilityIdentifier("drawing.reviewer.showOnPlotter")
        }
        Spacer()
        if busy { ProgressView().controlSize(.small) }
        if let failure { Text(failure).font(.caption).foregroundStyle(.red).lineLimit(2) }
        switch application.portraitStudio.sketches.persistenceState {
        case .loading:
          ProgressView("Loading Imaginations…").controlSize(.small)
        case .failed(let reason):
          Text("Imaginations library: \(reason)").font(.caption).foregroundStyle(.red).lineLimit(3)
          Button("Retry Library") { application.portraitStudio.sketches.retryPersistence() }
        case .pending:
          Text("Saving Imaginations…").font(.caption).foregroundStyle(.secondary)
        case .saved: EmptyView()
        }
      }
    }
    .padding(18).frame(minWidth: 940, minHeight: 660)
    .task {
      await application.portraitStudio.loadArchive()
      reconcileSelection()
    }
    .onAppear { reconcileSelection() }
    .onChange(of: selections) { reconcileSelection() }
    .accessibilityIdentifier("drawing.reviewer")
  }

  private func resultTitle(_ record: DrawingRunEvidenceRecord) -> String {
    if let id = record.attemptEvidence?.intent.context.candidate?.candidateID,
      let saved = drawings.first(where: { $0.id == id }) { return saved.candidate.recipe.title }
    if record.program.source?.kind == "portrait" { return "Portrait" }
    if let source = record.program.source?.sourceIdentifier,
      let entry = DrawingProgramCatalog.entries.first(where: { source.hasPrefix($0.sourceIdentifier) }) {
      return entry.displayName
    }
    return "Drawing"
  }

  private func reconcileSelection() {
    if selection.map({ !selections.contains($0) }) ?? true { selection = selections.first }
  }

  private func deleteResult(_ record: DrawingRunEvidenceRecord) {
    busy = true; failure = nil
    Task { @MainActor in
      do { try await application.deleteDrawingReview(recordID: record.recordID) }
      catch { failure = "Delete failed: \(error.localizedDescription)" }
      busy = false
    }
  }

  private func deleteDrawing(_ candidate: PortraitCandidate) {
    application.portraitStudio.sketches.remove(candidate.id)
  }

  private func deleteSource(_ candidate: PortraitCandidate) {
    application.portraitStudio.sketches.deleteSource(candidate.sourceSHA256)
  }
}

private enum DrawingReviewSelection: Hashable {
  case drawing(String)
  case result(DrawingEvidenceRecordID)
}

private struct DrawingReviewResult: View {
  let application: PlotterApplicationRuntime
  let record: DrawingRunEvidenceRecord
  let candidate: PortraitCandidate?
  let originalPixels: Bool
  @State private var images: [CGImage] = []
  @State private var failure: String?
  @State private var loading = true
  @State private var baselineIndex = 0
  @State private var resultIndex = 0
  private var baselineCount: Int { record.attemptEvidence?.baselines.count ?? 0 }
  private var resultCount: Int { max(0, images.count - baselineCount) }
  private var program: DrawingProgram? {
    candidate?.program ?? record.attemptEvidence?.intent.context.candidate?.sourceProgram
      ?? record.attemptEvidence?.intent.context.program
  }

  private var geometry: DrawingReviewGeometry? {
    DrawingReviewGeometry.resolve(plan: record.plan.executionPlan, sourceProgram: program)
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(physicalExecutionLabel(record.executionDisposition)).font(.headline)
        StudioHelpButton("Run details", text: physicalExecutionSummary(record.executionDisposition)
          + "\nRun \(record.runID)\n" + (record.attemptEvidence?.missingCoverageReason
            ?? "Coverage is retained per pixel. Raw images do not prove unseen regions are clear."))
        Spacer()
      }
      if let geometry {
        HStack(spacing: 12) {
          if let candidate {
            reviewPanel("Source") {
              DrawingReviewSource(candidate: candidate, originalPixels: originalPixels)
                .id(candidate.sourceSHA256)
            }
          }
          reviewPanel(geometry.title) {
            VStack(spacing: 4) {
              PortraitPlaneProgramPreview(preview: geometry.preview)
              Text(geometry.explanation).font(.caption).foregroundStyle(.secondary)
            }
          }
        }.frame(maxHeight: 210)
      } else {
        Text(DrawingReviewGeometry.unavailableExplanation)
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        reviewPanel("Baseline") {
          if images.indices.contains(baselineIndex), baselineIndex < baselineCount {
            DrawingReviewImage(image: images[baselineIndex], originalPixels: originalPixels)
          } else { imageUnavailable(referenceCount: record.attemptEvidence?.baselines.count) }
        }
        reviewPanel("Result") {
          if resultCount > resultIndex, images.indices.contains(baselineCount + resultIndex) {
            DrawingReviewImage(image: images[baselineCount + resultIndex], originalPixels: originalPixels)
          } else { imageUnavailable(referenceCount: record.attemptEvidence?.terminalFrames.count) }
        }
      }
      if baselineCount > 1 || resultCount > 1 {
        HStack {
          if baselineCount > 1 {
            Picker("Baseline", selection: $baselineIndex) {
              ForEach(0..<baselineCount, id: \.self) { Text("\($0 + 1)").tag($0) }
            }
          }
          if resultCount > 1 {
            Picker("Result", selection: $resultIndex) {
              ForEach(0..<resultCount, id: \.self) { Text("\($0 + 1)").tag($0) }
            }
          }
        }
      }
      if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
    }
    .task(id: record.recordID) {
      loading = true; images = []; failure = nil; baselineIndex = 0; resultIndex = 0
      defer { loading = false }
      guard record.attemptEvidence != nil else { return }
      do {
        let originals = try await application.physicalAttemptImages(record)
        guard !Task.isCancelled else { return }
        images = try originals.map { frame in
          guard let image = FrameImageFactory.image(from: frame.frame) else {
            throw DrawingRunEvidenceError.invalidMediaReference
          }
          return image
        }
      } catch { if !Task.isCancelled { failure = "Images unavailable: \(error.localizedDescription)" } }
    }
  }

  private func imageUnavailable(referenceCount: Int?) -> some View {
    Group {
      if loading { ProgressView() }
      else {
        ContentUnavailableView("Photograph unavailable", systemImage: "photo",
          description: Text(DrawingReviewGeometry.photographExplanation(
            referenceCount: referenceCount, failed: failure != nil)))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct DrawingReviewSource: View {
  let candidate: PortraitCandidate
  let originalPixels: Bool
  @State private var image: CGImage?
  @State private var loading = true
  var body: some View {
    Group {
      if let image { DrawingReviewImage(image: image, originalPixels: originalPixels) }
      else if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
      else { ContentUnavailableView("Source unavailable", systemImage: "photo") }
    }.task(id: candidate.sourceSHA256) {
      image = nil; loading = true
      let data = candidate.sourceData
      let decoded = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil as CGImage? }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ] as CFDictionary)
      }.value
      if !Task.isCancelled { image = decoded; loading = false }
    }
  }
}

private struct DrawingReviewImage: View {
  let image: CGImage
  let originalPixels: Bool
  var body: some View {
    Group {
      if originalPixels {
        ScrollView([.horizontal, .vertical]) {
          Image(decorative: image, scale: 1).resizable()
            .frame(width: CGFloat(image.width), height: CGFloat(image.height))
        }
      } else {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.clipped()
  }
}

private func referencePreview(_ program: DrawingProgram) -> PortraitPlanePreview {
  PortraitPlanePreviewSource().resolve(program: program,
    nominalWidth: program.strokes.first?.style.nominalLineWidth ?? 0.4)
}

private func reviewPanel<Content: View>(_ title: String,
  @ViewBuilder content: () -> Content) -> some View {
  VStack(alignment: .leading, spacing: 5) {
    Text(title).font(.caption).foregroundStyle(.secondary)
    content().frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.white).border(.quaternary)
  }.frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func physicalExecutionLabel(_ disposition: DrawingRunExecutionDisposition) -> String {
  switch disposition {
  case .completed: "Controller completed"
  case .refused: "Refused"
  case .cancelled: "Stopped"
  case .ambiguous: "Uncertain"
  case .failed: "Failed"
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
