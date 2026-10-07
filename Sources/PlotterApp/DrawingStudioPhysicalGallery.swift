import ImageIO
import PlotterModel
import PlotterRuntime
import SwiftUI

/// One metadata browser for generated variants, saved drawings and later physical runs.
/// Selection is local; inspecting an item never changes a live run or its paper facts.
struct DrawingReviewerView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  var showOnPlotter: ((SavedDrawing) async -> String?)? = nil
  var initialPhotoID: UUID? = nil
  var inspectInStudio: ((String) async -> String?)? = nil
  @State private var selection: DrawingReviewSelection?
  @State private var explicitSelection = false
  @State private var onlyCurrentPhoto = false
  @State private var onlyKept = false
  @State private var physicalLimit = 100
  @State private var originalPixels = false
  @State private var selectedDrawing: SavedDrawing?
  @State private var busy = false
  @State private var failure: String?

  init(application: PlotterApplicationRuntime, close: @escaping () -> Void,
    showOnPlotter: ((SavedDrawing) async -> String?)? = nil, initialPhotoID: UUID? = nil,
    inspectInStudio: ((String) async -> String?)? = nil) {
    self.application = application; self.close = close; self.showOnPlotter = showOnPlotter
    self.initialPhotoID = initialPhotoID; self.inspectInStudio = inspectInStudio
    _onlyCurrentPhoto = State(initialValue: initialPhotoID != nil)
  }

  private var library: PortraitSketchCollection { application.portraitStudio.sketches }
  private var drawings: [SavedDrawingSummary] {
    library.drawingSummaries.filter {
      (!onlyCurrentPhoto || $0.photoID == initialPhotoID)
        && (!onlyKept || $0.isSaved || $0.feedback == .promising)
    }
  }
  private var results: [DrawingRunEvidenceRecord] {
    let matching = application.drawingReviewRecords.filter { value in
      !onlyCurrentPhoto || drawings.contains { linked(value, to: $0) }
    }
    return Array(matching.reversed().prefix(physicalLimit))
  }
  private var interrupted: [DrawingRunAttemptState] {
    let matching = application.drawingReviewIncompleteAttempts.filter { value in
      !onlyCurrentPhoto || drawings.contains { linked(value, to: $0) }
    }
    return Array(matching.reversed().prefix(physicalLimit))
  }
  private var selections: [DrawingReviewSelection] {
    let dated: [(DrawingReviewSelection, Date)] = drawings.map { (.drawing($0.id), $0.createdAt) }
      + interrupted.map { (.attempt($0.intent.runID), $0.intent.recordedAt.wallTime) }
      + results.map { (.result($0.recordID), $0.recordedAt.wallTime) }
    return dated.sorted { $0.1 > $1.1 }.map(\.0)
  }
  private var record: DrawingRunEvidenceRecord? {
    guard case .result(let id) = selection else { return nil }
    return results.first { $0.recordID == id }
  }
  private var interruptedAttempt: DrawingRunAttemptState? {
    guard case .attempt(let id) = selection else { return nil }
    return interrupted.first { $0.intent.runID == id }
  }
  private var summary: SavedDrawingSummary? {
    guard case .drawing(let id) = selection else { return nil }
    return drawings.first { $0.id == id }
  }
  private var noteScope: DrawingReviewNoteScope? {
    if let record { return .run(record.runID) }
    if let interruptedAttempt { return .run(interruptedAttempt.intent.runID) }
    if let summary { return .drawing(summary.id) }
    return nil
  }
  private var sourceGroups: [String] {
    var seen = Set<String>()
    return drawings.compactMap { value in
      let key = value.sourceSHA256 ?? value.photoID?.uuidString ?? "source-free"
      return seen.insert(key).inserted ? key : nil
    }
  }
  private func variants(_ key: String) -> [SavedDrawingSummary] {
    drawings.filter { ($0.sourceSHA256 ?? $0.photoID?.uuidString ?? "source-free") == key }
  }
  private func linked(_ record: DrawingRunEvidenceRecord, to drawing: SavedDrawingSummary) -> Bool {
    DrawingReviewLinkage.matches(record: record, drawingID: drawing.id, programContentHash: drawing.programContentHash)
  }
  private func linked(_ attempt: DrawingRunAttemptState, to drawing: SavedDrawingSummary) -> Bool {
    DrawingReviewLinkage.matches(intent: attempt.intent, drawingID: drawing.id, programContentHash: drawing.programContentHash)
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Drawings").font(.title2)
        StudioHelpButton("Drawings", text: "Each photo groups its generated and saved drawing variants. Physical runs appear under their exact source drawing. Historical runs without a retained source remain available. Browsing does not replace the current edit or move the plotter. Send to Drawing restores the exact selected program for placement. Notes are operator text and do not establish drawing completion or observed ink.")
        Spacer()
        Picker("Image size", selection: $originalPixels) {
          Text("Fit").tag(false); Text("100%").tag(true)
        }.pickerStyle(.segmented).frame(width: 140)
        Button("Close", action: close).keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("drawing.reviewer.close")
      }
      HStack {
        if initialPhotoID != nil { Toggle("Current photo", isOn: $onlyCurrentPhoto) }
        Toggle("Kept only", isOn: $onlyKept)
        Spacer()
        if library.drawingHasMore {
          Button("Load more drawings") { Task { await library.loadMoreDrawings() } }
            .accessibilityIdentifier("drawing.reviewer.moreDrawings")
        }
        if application.drawingReviewRecords.count > results.count || application.drawingReviewIncompleteAttempts.count > interrupted.count {
          Button("Load more runs") { physicalLimit += 100 }
        }
      }.toggleStyle(.checkbox).controlSize(.small)
      HSplitView {
        List(selection: Binding(get: { selection }, set: { selection = $0; explicitSelection = true })) {
          ForEach(sourceGroups, id: \.self) { key in
            Section(groupTitle(key)) {
              ForEach(variants(key)) { drawing in
                VStack(alignment: .leading, spacing: 3) {
                  Label(drawing.title, systemImage: drawing.isSaved ? "doc.text.image" : "pencil.line")
                  Text("\(drawing.strokeCount) strokes · \(drawing.isSaved ? "Saved" : "Generated")")
                    .font(.caption).foregroundStyle(.secondary)
                }.tag(DrawingReviewSelection.drawing(drawing.id))
                  .accessibilityIdentifier("drawing.reviewSaved.\(drawing.id)")
                  .contextMenu { variantActions(drawing) }
                ForEach(results.filter { linked($0, to: drawing) }, id: \.recordID) { value in resultRow(value, indented: true) }
                ForEach(interrupted.filter { linked($0, to: drawing) }, id: \.intent.runID) { value in attemptRow(value, indented: true) }
              }
            }
          }
          Section("Other historical runs") {
            ForEach(results.filter { value in !drawings.contains { linked(value, to: $0) } }, id: \.recordID) { value in resultRow(value, indented: false) }
            ForEach(interrupted.filter { value in !drawings.contains { linked(value, to: $0) } }, id: \.intent.runID) { value in attemptRow(value, indented: false) }
          }
        }.frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
          .accessibilityIdentifier("drawing.reviewer.items")
        VStack(spacing: 10) {
          Group {
            if let interruptedAttempt {
              DrawingReviewInterruptedAttempt(application: application, attempt: interruptedAttempt,
                originalPixels: originalPixels).id(interruptedAttempt.intent.runID)
            } else if let record {
              DrawingReviewResult(application: application, record: record, originalPixels: originalPixels).id(record.recordID)
            } else if let drawing = selectedDrawing, drawing.id == summary?.id {
              HStack(spacing: 12) {
                if let source = drawing.sourceImageData, let hash = drawing.sourceImageSHA256 {
                  reviewPanel("Source photo") { DrawingReviewSource(data: source, sourceSHA256: hash,
                    originalPixels: originalPixels).id(hash) }
                }
                reviewPanel("Drawing") { PortraitPlaneProgramPreview(preview: referencePreview(drawing.program)) }
              }
            } else if let summary {
              if failure != nil {
                ContentUnavailableView("Drawing unavailable", systemImage: "exclamationmark.triangle",
                  description: Text(failure ?? ""))
                Button("Retry Selected Drawing") {
                  let id = summary.id
                  perform {
                    do { selectedDrawing = try await library.drawingForBrowsing(id); return nil }
                    catch { return error.localizedDescription }
                  }
                }
              } else { ProgressView("Loading selected drawing…") }
            } else {
              ContentUnavailableView("No drawings in this view", systemImage: "rectangle.stack")
            }
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          if let noteScope {
            DrawingReviewNotes(application: application, scope: noteScope).id(noteScope)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      HStack {
        if let record {
          Button("Delete Run Review", role: .destructive) { deleteResult(record) }.disabled(busy)
            .accessibilityIdentifier("drawing.reviewer.deleteResult")
        } else if let interruptedAttempt {
          Button("Dismiss Unfinished Run", role: .destructive) { dismissAttempt(interruptedAttempt) }.disabled(busy)
            .accessibilityIdentifier("drawing.reviewer.dismissAttempt")
        } else if let summary {
          Button("Delete Drawing", role: .destructive) { application.portraitStudio.deleteAttempt(summary.id) }.disabled(busy)
          if let candidate = selectedDrawing?.portraitCandidate {
            Button("Delete Source and Its Drawings", role: .destructive) { library.deleteSource(candidate.sourceSHA256) }.disabled(busy)
          }
          if let drawing = selectedDrawing, !summary.isSaved {
            Button("Save Drawing") { perform { await library.saveDrawing(drawing) } }.disabled(busy)
          }
          if selectedDrawing?.portraitCandidate != nil, let inspectInStudio {
            Button("Inspect in Portrait Studio") {
              let id = summary.id
              perform {
                let error = await inspectInStudio(id)
                if error == nil { close() }
                return error
              }
            }.disabled(busy)
          }
        }
        if record != nil || interruptedAttempt != nil {
          StudioHelpButton("Remove review", text: "Hides this item durably from review. Original attempts, possible-ink and no-redraw facts, and shared media remain retained. This never declares paper clear or authorizes drawing again.")
        }
        if let drawing = selectedDrawing, summary?.id == drawing.id, let showOnPlotter {
          Button("Send to Drawing", systemImage: "video") {
            perform {
              let error = await showOnPlotter(drawing)
              if error == nil { close() }
              return error
            }
          }.disabled(busy).accessibilityIdentifier("drawing.reviewer.showOnPlotter")
        }
        Spacer()
        if busy { ProgressView().controlSize(.small) }
        if let failure { Text(failure).font(.caption).foregroundStyle(.red).lineLimit(2) }
        if case .failed(let reason) = library.drawingBrowserState {
          Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
          Button("Retry Library") { Task { await library.loadDrawingBrowser() } }
        }
      }
    }.padding(18).frame(minWidth: 1000, minHeight: 700)
      .task { await application.portraitStudio.loadPhotoBrowser() }
      .task(id: selection) {
        selectedDrawing = nil; failure = nil
        guard case .drawing(let id) = selection else { return }
        do {
          let drawing = try await library.drawingForBrowsing(id)
          try Task.checkCancellation()
          guard selection == .drawing(id) else { return }
          selectedDrawing = drawing
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
      }
      .onChange(of: selections) { reconcileSelection() }
      .task(id: onlyCurrentPhoto) {
        await library.loadDrawingBrowser(photoID: onlyCurrentPhoto ? initialPhotoID : nil)
        reconcileSelection()
      }
      .accessibilityIdentifier("drawing.reviewer")
  }

  private func groupTitle(_ key: String) -> String {
    guard key != "source-free" else { return "Drawings without a photo" }
    if let id = variants(key).first?.photoID,
      let photo = application.portraitStudio.photoListItems.first(where: { $0.id == id }) {
      let date = library.photoReferences.first(where: { $0.id == id })?.capturedAt ?? variants(key).first?.createdAt
      return "\(photo.label) · \(date?.formatted(date: .abbreviated, time: .shortened) ?? "") · \(key.prefix(8))"
    }
    let date = variants(key).first?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? ""
    return "Source photo · \(date) · \(key.prefix(8))"
  }
  @ViewBuilder private func variantActions(_ drawing: SavedDrawingSummary) -> some View {
    if drawing.feedback != nil {
      Button("Mark promising") { library.setFeedback(.promising, for: drawing.id) }
      Button("Mark rejected") { library.setFeedback(.rejected, for: drawing.id) }
      Button("Clear feedback") { library.setFeedback(.unknown, for: drawing.id) }
    }
    Button("Delete Drawing", role: .destructive) { application.portraitStudio.deleteAttempt(drawing.id) }
  }
  private func resultRow(_ value: DrawingRunEvidenceRecord, indented: Bool) -> some View {
    Label(physicalExecutionLabel(value.executionDisposition), systemImage: "photo")
      .padding(.leading, indented ? 20 : 0).tag(DrawingReviewSelection.result(value.recordID))
      .accessibilityIdentifier("drawing.reviewResult.\(value.recordID)")
  }
  private func attemptRow(_ value: DrawingRunAttemptState, indented: Bool) -> some View {
    Label("Unfinished run · \(value.progressFrames.count) stages", systemImage: "photo.stack")
      .padding(.leading, indented ? 20 : 0).tag(DrawingReviewSelection.attempt(value.intent.runID))
  }
  private func reconcileSelection() {
    selection = DrawingReviewSelectionPolicy.reconcile(current: selection, available: selections,
      explicitlySelected: explicitSelection)
  }
  private func perform(_ action: @escaping @MainActor () async -> String?) {
    busy = true; failure = nil
    Task { @MainActor in failure = await action(); busy = false }
  }
  private func deleteResult(_ record: DrawingRunEvidenceRecord) {
    perform {
      do { try await application.deleteDrawingReview(recordID: record.recordID); return nil }
      catch { return "Delete failed: \(error.localizedDescription)" }
    }
  }
  private func dismissAttempt(_ attempt: DrawingRunAttemptState) {
    perform {
      do { try await application.dismissDrawingAttemptReview(runID: attempt.intent.runID); return nil }
      catch { return "Dismiss failed: \(error.localizedDescription)" }
    }
  }
}

enum DrawingReviewSelection: Hashable {
  case attempt(RunID), drawing(String), result(DrawingEvidenceRecordID)
}

enum DrawingReviewSelectionPolicy {
  static func reconcile(current: DrawingReviewSelection?, available: [DrawingReviewSelection],
    explicitlySelected: Bool) -> DrawingReviewSelection? {
    if explicitlySelected, let current, available.contains(current) { return current }
    return available.first
  }
}

private struct DrawingReviewNotes: View {
  let application: PlotterApplicationRuntime
  let scope: DrawingReviewNoteScope
  @State private var text = ""
  @State private var saving = false
  @State private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Notes").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Save Notes") {
          let value = text
          saving = true; error = nil
          Task { @MainActor in
            do { try await application.saveDrawingReviewNote(scope: scope, text: value) }
            catch { self.error = error.localizedDescription }
            saving = false
          }
        }.disabled(saving || text == application.drawingEvidenceArchive.reviewNote(for: scope) || text.utf8.count > 8192)
      }
      TextEditor(text: $text).font(.body).frame(height: 70).border(.quaternary)
        .accessibilityIdentifier("drawing.reviewer.notes")
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      if text.utf8.count > 8192 { Text("Notes must fit in 8 KB.").font(.caption).foregroundStyle(.red) }
    }.task(id: scope) { text = application.drawingEvidenceArchive.reviewNote(for: scope) }
  }
}

private struct DrawingReviewResult: View {
  let application: PlotterApplicationRuntime
  let record: DrawingRunEvidenceRecord
  let originalPixels: Bool
  @State private var baselineIndex = 0
  @State private var resultIndex = 0
  init(application: PlotterApplicationRuntime, record: DrawingRunEvidenceRecord, originalPixels: Bool) {
    self.application = application; self.record = record; self.originalPixels = originalPixels
    _resultIndex = State(initialValue: record.attemptEvidence.map(DrawingReviewPhotographs.preferredStageIndex) ?? 0)
  }
  private var baselines: [DrawingRunMediaReference] { record.attemptEvidence?.baselines ?? [] }
  private var stages: [DrawingRunMediaReference] {
    (record.attemptEvidence?.progressFrames.map(\.media) ?? []) + (record.attemptEvidence?.terminalFrames ?? [])
  }
  private var stageLabels: [String] { record.attemptEvidence.map(DrawingReviewPhotographs.stageLabels) ?? [] }
  private var geometry: DrawingReviewGeometry? {
    let progress = record.attemptEvidence?.progressFrames ?? []
    return DrawingReviewGeometry.resolve(plan: record.plan.executionPlan,
      sourceProgram: record.attemptEvidence?.intent.context.candidate?.sourceProgram ?? record.attemptEvidence?.intent.context.program,
      completedStrokeCount: progress.indices.contains(resultIndex) ? progress[resultIndex].progress.completedStrokeIDs.count : nil)
  }
  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text(physicalExecutionLabel(record.executionDisposition)).font(.headline)
        StudioHelpButton("Run details", text: physicalExecutionSummary(record.executionDisposition)
          + "\nRun \(record.runID)\n" + (record.attemptEvidence?.missingCoverageReason ?? "Raw images do not prove unseen regions are clear."))
        Spacer()
      }
      if let geometry {
        PortraitPlaneProgramPreview(preview: geometry.preview).frame(maxHeight: 210)
        Text(geometry.explanation).font(.caption).foregroundStyle(.secondary)
      } else { Text(DrawingReviewGeometry.unavailableExplanation).font(.caption).foregroundStyle(.secondary) }
      HStack(spacing: 12) {
        reviewPanel("Baseline") {
          selectedPhoto(baselines, baselineIndex)
        }
        reviewPanel(stageLabels.indices.contains(resultIndex) ? stageLabels[resultIndex] : "Result") {
          selectedPhoto(stages, resultIndex)
        }
      }
      HStack {
        if baselines.count > 1 {
          Picker("Baseline", selection: $baselineIndex) {
            ForEach(baselines.indices, id: \.self) { Text("\($0 + 1)").tag($0) }
          }
        }
        if stages.count > 1 {
          Picker("Drawing stage", selection: $resultIndex) {
            ForEach(stages.indices, id: \.self) { index in Text(stageLabels.indices.contains(index) ? stageLabels[index] : "Frame \(index + 1)").tag(index) }
          }
        }
      }
      if let status = DrawingReviewPhotographs.status(record) {
        Text(status).font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("drawing.reviewer.photoStatus")
      }
    }
  }
  @ViewBuilder private func selectedPhoto(_ references: [DrawingRunMediaReference], _ index: Int) -> some View {
    if references.indices.contains(index) {
      DrawingReviewRetainedPhoto(application: application, reference: references[index], runID: record.runID,
        originalPixels: originalPixels).id(references[index])
    } else {
      ContentUnavailableView("Photograph unavailable", systemImage: "photo",
        description: Text(DrawingReviewGeometry.photographExplanation(referenceCount: references.count, failed: false)))
    }
  }
}

private struct DrawingReviewInterruptedAttempt: View {
  let application: PlotterApplicationRuntime
  let attempt: DrawingRunAttemptState
  let originalPixels: Bool
  @State private var selectedStage = 0
  @State private var baselineIndex = 0
  init(application: PlotterApplicationRuntime, attempt: DrawingRunAttemptState, originalPixels: Bool) {
    self.application = application; self.attempt = attempt; self.originalPixels = originalPixels
    _selectedStage = State(initialValue: max(0, attempt.progressFrames.count - 1))
  }
  var body: some View {
    VStack(spacing: 10) {
      Text("Run did not publish a final result").font(.headline)
      Text("Retained evidence remains available; drawing completion is unknown.").font(.caption).foregroundStyle(.secondary)
      if let geometry = DrawingReviewGeometry.resolve(plan: attempt.intent.plan,
        sourceProgram: attempt.intent.context.candidate?.sourceProgram ?? attempt.intent.context.program,
        completedStrokeCount: attempt.progressFrames.indices.contains(selectedStage)
          ? attempt.progressFrames[selectedStage].progress.completedStrokeIDs.count : nil) {
        PortraitPlaneProgramPreview(preview: geometry.preview).frame(maxHeight: 210)
      }
      HStack(spacing: 12) {
        reviewPanel("Baseline") {
          if attempt.baselines.indices.contains(baselineIndex) {
            DrawingReviewRetainedPhoto(application: application, reference: attempt.baselines[baselineIndex],
              runID: attempt.intent.runID, originalPixels: originalPixels).id(attempt.baselines[baselineIndex])
          } else { ContentUnavailableView("No baseline retained", systemImage: "photo") }
        }
        reviewPanel("Drawing stage") {
          if attempt.progressFrames.indices.contains(selectedStage) {
            let media = attempt.progressFrames[selectedStage].media
            DrawingReviewRetainedPhoto(application: application, reference: media,
              runID: attempt.intent.runID, originalPixels: originalPixels).id(media)
          } else { ContentUnavailableView("No stage retained", systemImage: "photo") }
        }
      }
      HStack {
        if attempt.baselines.count > 1 {
          Picker("Baseline", selection: $baselineIndex) {
            ForEach(attempt.baselines.indices, id: \.self) { Text("\($0 + 1)").tag($0) }
          }
        }
        if !attempt.progressFrames.isEmpty {
          Picker("Drawing stage", selection: $selectedStage) {
            ForEach(attempt.progressFrames.indices, id: \.self) { index in
              let progress = attempt.progressFrames[index].progress
              Text("\(progress.completedStrokeIDs.count)/\(progress.plannedStrokeCount) strokes").tag(index)
            }
          }
        }
      }
    }
  }
}

private struct DrawingReviewRetainedPhoto: View {
  let application: PlotterApplicationRuntime
  let reference: DrawingRunMediaReference
  let runID: RunID
  let originalPixels: Bool
  @State private var image: CGImage?
  @State private var failure: String?
  @State private var loading = true
  @State private var notesPresented = false
  private var noteScope: DrawingReviewNoteScope {
    .media("\(runID)|\(reference.frame.frameID)|\(reference.frame.captureNanoseconds)|\(reference.frame.frameSHA256)")
  }
  var body: some View {
    Group {
      if let image { DrawingReviewImage(image: image, originalPixels: originalPixels) }
      else if loading { ProgressView() }
      else { ContentUnavailableView("Photograph unavailable", systemImage: "photo", description: Text(failure ?? "Retained pixels unavailable.")) }
    }.overlay(alignment: .bottomTrailing) {
      Button("Photo Notes", systemImage: "note.text") { notesPresented = true }
        .padding(6).popover(isPresented: $notesPresented) {
          DrawingReviewNotes(application: application, scope: noteScope).padding(12).frame(width: 360)
        }
    }.task(id: reference) {
      image = nil; failure = nil; loading = true
      defer { if !Task.isCancelled { loading = false } }
      do {
        let frame = try await application.drawingReviewImage(reference, runID: runID)
        try Task.checkCancellation()
        guard let decoded = FrameImageFactory.image(from: frame.frame) else { throw DrawingRunEvidenceError.invalidMediaReference }
        image = decoded
      } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
  }
}

private struct DrawingReviewSource: View {
  let data: Data
  let sourceSHA256: String
  let originalPixels: Bool
  @State private var image: CGImage?
  @State private var loading = true
  var body: some View {
    Group {
      if let image { DrawingReviewImage(image: image, originalPixels: originalPixels) }
      else if loading { ProgressView() }
      else { ContentUnavailableView("Source unavailable", systemImage: "photo") }
    }.task(id: sourceSHA256) {
      image = nil; loading = true
      let data = data
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
          Image(decorative: image, scale: 1).resizable().frame(width: CGFloat(image.width), height: CGFloat(image.height))
        }
      } else {
        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.clipped()
  }
}

private func referencePreview(_ program: DrawingProgram) -> PortraitPlanePreview {
  PortraitPlanePreviewSource().resolve(program: program, nominalWidth: program.strokes.first?.style.nominalLineWidth ?? 0.4)
}
private func reviewPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
  VStack(alignment: .leading, spacing: 5) {
    Text(title).font(.caption).foregroundStyle(.secondary)
    content().frame(maxWidth: .infinity, maxHeight: .infinity).background(.white).border(.quaternary)
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
