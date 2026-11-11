import PortraitArtists
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import ImageIO
import PlotterModel
import PlotterRuntime
import SwiftUI
import AppKit

/// Review visibility comes from the raw owner's projections. A hidden terminal
/// is still a terminal and must never become a synthetic incomplete attempt.
struct DrawingReviewRawRows {
  let records: [DrawingRunEvidenceRecord]
  let incomplete: DrawingRunAttemptState?
  static func resolve(run: RunID, archive: DrawingRunEvidenceArchive) -> Self {
    .init(records: archive.reviewRecords.filter { $0.role == .ordinaryDrawing && $0.runID == run },
      incomplete: archive.reviewIncompleteAttempts.first { $0.intent.role == .ordinaryDrawing && $0.intent.runID == run })
  }
}

/// Raw archive revision counts terminal records. Attempt dispatch, appended
/// media and review visibility can change independently of that count.
struct DrawingReviewRefreshKey: Hashable {
  struct Media: Hashable {
    let frame: FrameID
    let captured: UInt64
    let digest: String
    init(_ value: DrawingRunMediaReference) {
      frame = value.frame.frameID; captured = value.frame.captureNanoseconds; digest = value.frame.frameSHA256
    }
  }
  struct Progress: Hashable {
    let media: Media
    let completedStrokes: Int
  }
  struct Attempt: Hashable {
    let run: RunID
    let request: UUID
    let possibleInk: Bool
    let baselines: [Media]
    let progress: [Progress]
  }
  let archive: UUID
  let revision: UInt64
  let attempts: [Attempt]
  let deleted: [DrawingEvidenceRecordID]
  let dismissed: [RunID]
  init(_ archive: DrawingRunEvidenceArchive) {
    self.archive = archive.archiveID; revision = archive.revision
    deleted = archive.deletedReviewRecordIDs; dismissed = archive.dismissedReviewRunIDs
    attempts = archive.attempts.map { attempt in
      .init(run: attempt.intent.runID, request: attempt.intent.requestID, possibleInk: attempt.inkDispatchPossible,
        baselines: attempt.baselines.map(Media.init),
        progress: attempt.progressFrames.map { .init(media: .init($0.media), completedStrokes: $0.progress.completedStrokeIDs.count) })
    }
  }
}

/// Browsing reads compact metadata. Only an explicit selection materializes its verified drawing.
struct DrawingReviewerView: View {
  let application: PlotterApplicationRuntime
  let drawing: Drawing
  @Environment(\.drawingPresentationPolicy) private var presentationPolicy
  @State private var failure: String?
  @State private var originalPixels = false
  @State private var records: [DrawingRunEvidenceRecord] = []
  @State private var staged: [DrawingRunAttemptState] = []
  @State private var attributionFailures: [String] = []
  @State private var incomplete: [DrawingRunAttemptState] = []
  @State private var portable: [DrawingLibraryAttemptEntry] = []
  @State private var rawCursor: DrawingLibraryRecordCursor?
  @State private var portableCursor: DrawingLibraryAttemptCursor?
  @State private var generation = UUID()
  @State private var loadGeneration = UUID()
  @State private var isClosed = false
  @State private var exporting: JobRef?
  @State private var exportStatus: String?
  @State private var activePanel: NSSavePanel?
  private var library: DrawingLibrary { application.portraitStudio.library }
  private var exportPresentationIsOpen: Bool {
    application.drawingDestinationRecoveryAdmissionIsOpen
      && (NSApplication.shared.delegate as? AdaptivePlotterApplicationDelegate)?.drawingPresentationAdmissionIsOpen != false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Attempts").font(.title2)
      Text("\(portable.count) declared result runs loaded · \(records.count + incomplete.count) raw attempted runs loaded")
        .font(.caption).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 12) {
            if let ref = drawing.reference {
              Text(ref.revision.uuidString).font(.caption).textSelection(.enabled)
              if records.isEmpty && staged.isEmpty && portable.isEmpty && incomplete.isEmpty { Text("No attributable attempts for this Drawing.").foregroundStyle(.secondary) }
              ForEach(attributionFailures, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
              ForEach(staged, id: \.intent.runID) { attempt in
                Text("Run \(attempt.intent.runID.rawValue): staged before Start; not an attempted run or ink evidence").font(.caption).foregroundStyle(.secondary)
                exportButton(for: attempt.intent)
              }
              ForEach(incomplete, id: \.intent.runID) { attempt in
                Text("Run \(attempt.intent.runID.rawValue) · possible ink; terminal result unavailable").font(.headline)
                Text("Raw owner dispatch classification; execution environment is not retained here.").font(.caption).foregroundStyle(.secondary)
                exportButton(for: attempt.intent)
                let media = attempt.baselines + attempt.progressFrames.map(\.media)
                ForEach(Array(media.enumerated()), id: \.offset) { _, reference in
                  DrawingReviewRetainedPhoto(application: application, reference: reference,
                    runID: attempt.intent.runID, originalPixels: originalPixels).frame(height: 240)
                }
                DrawingReviewNotes(application: application, scope: .run(attempt.intent.runID))
              }
              ForEach(portable, id: \.snapshot) { entry in
                VStack(alignment: .leading) {
                  Text("Result snapshot for run \(entry.run)").font(.headline)
                  Text("\(entry.environment) · \(entry.state) · \(entry.dispatch) · \(entry.observation)").font(.caption)
                  Text("Declared snapshot; raw photographs and execution authority remain with their archive.").font(.caption).foregroundStyle(.secondary)
                  ForEach(entry.unsupportedReasons, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
              }
              ForEach(records, id: \.recordID) { record in
                Text("Run \(record.runID.rawValue)").font(.headline)
                Text("Raw execution environment unavailable in this record.").font(.caption).foregroundStyle(.secondary)
                Text(String(describing: record.executionDisposition)).font(.caption)
                if let attempt = record.attemptEvidence {
                  exportButton(for: attempt.intent)
                  let media = attempt.baselines + attempt.progressFrames.map(\.media) + attempt.terminalFrames
                  ForEach(Array(media.enumerated()), id: \.offset) { _, reference in
                    DrawingReviewRetainedPhoto(application: application, reference: reference,
                      runID: record.runID, originalPixels: originalPixels).frame(height: 240)
                  }
                }
                DrawingReviewNotes(application: application, scope: .run(record.runID))
              }
              Toggle("Original image pixels", isOn: $originalPixels)
              DrawingReviewNotes(application: application, scope: .drawing(ref.digest.description))
              if rawCursor != nil || portableCursor != nil {
                Button("More Attempts") { Task { await load(more: true) } }
              }
            } else { Text("Select a drawing.").foregroundStyle(.secondary) }
          }.padding()
      if let failure { Text(failure).foregroundStyle(.red) }
      if let exportStatus { Text(exportStatus).font(.caption) }
      if exporting != nil { ProgressView("Preparing run result export").controlSize(.small) }
    }.padding()
      .onAppear { isClosed = false; generation = UUID() }
      .task(id: DrawingReviewRefreshKey(application.drawingEvidenceArchive)) { await load() }
      .onDisappear { isClosed = true; generation = UUID(); loadGeneration = UUID(); activePanel?.cancel(nil) }
      .onChange(of: presentationPolicy.modalUnavailableReason) { _, reason in if reason != nil { activePanel?.cancel(nil) } }
      .onChange(of: application.drawingDestinationRecoveryAdmissionIsOpen) { _, open in if !open { activePanel?.cancel(nil) } }
  }
  @ViewBuilder private func exportButton(for intent: DrawingRunIntent) -> some View {
    if let binding = intent.issuance, binding.drawing == drawing.reference {
      Button("Export Run Result") { Task { await export(binding) } }
        .disabled(exporting != nil)
        .accessibilityIdentifier("drawing.reviewer.exportRunResult")
    }
  }
  private func export(_ binding: DrawingJobIssuance) async {
    guard let ref = drawing.reference, binding.drawing == ref, !isClosed,
      exportPresentationIsOpen, exporting == nil else { return }
    if let reason = presentationPolicy.modalUnavailableReason { exportStatus = "Run result export: " + reason; return }
    let request = generation
    exporting = binding.job; exportStatus = nil
    defer { if request == generation { exporting = nil } }
    func isCurrent() -> Bool {
      !isClosed && request == generation && drawing.reference == ref && !Task.isCancelled
        && exportPresentationIsOpen
    }
    do {
      let result = try await DrawingRunResultExport.prepare(binding: binding, drawing: ref, destination: application.drawingDestination)
      defer { result.discard() }
      guard isCurrent() else { return }
      if let reason = presentationPolicy.modalUnavailableReason { exportStatus = "Run result export: " + reason; return }
      let panel = NSSavePanel()
      panel.title = "Export Run Result"; panel.nameFieldStringValue = "Run-\(binding.job.job.uuidString).zip"
      activePanel = panel; defer { if activePanel === panel { activePanel = nil } }
      guard await panel.begin() == .OK, let url = panel.url, isCurrent(), presentationPolicy.modalUnavailableReason == nil else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try await result.save(to: url)
      guard isCurrent() else { return }
      exportStatus = "Run result exported. This read-only delivery does not authorize another run."
    } catch {
      if isCurrent() { exportStatus = "Run result export failed: " + error.localizedDescription }
    }
  }
  private func load(more: Bool = false) async {
    guard let ref = drawing.reference, !isClosed else { return }
    if !more { loadGeneration = UUID(); failure = nil; records = []; staged = []; attributionFailures = []; incomplete = []; portable = []; rawCursor = nil; portableCursor = nil }
    let request = loadGeneration
    do {
      if !more || rawCursor != nil {
        let page = try await PortraitDrawingAttemptBinding.page(for: ref, library: library, after: more ? rawCursor : nil)
        guard !Task.isCancelled, !isClosed, request == loadGeneration, drawing.reference == ref else { return }
        for record in page.entries {
          do {
            let binding = try PortraitDrawingAttemptBinding.decode(record, for: ref)
            let state = try binding.verify(in: application.drawingEvidenceArchive, at: application.drawingEvidencePort.archiveURL, drawing: drawing)
            let visible = DrawingReviewRawRows.resolve(run: state.intent.runID, archive: application.drawingEvidenceArchive)
            let matches = visible.records
            for match in matches where !records.contains(where: { $0.runID == match.runID }) { records.append(match) }
            if matches.isEmpty, let state = visible.incomplete, state.inkDispatchPossible {
              if !incomplete.contains(where: { $0.intent.runID == state.intent.runID }) { incomplete.append(state) }
            } else if matches.isEmpty, let state = visible.incomplete {
              if !staged.contains(where: { $0.intent.runID == state.intent.runID }) { staged.append(state) }
            }
          } catch { attributionFailures.append("Raw attribution unavailable: " + error.localizedDescription) }
        }
        rawCursor = page.next
      }
      if !more || portableCursor != nil {
        let page = try await library.attempts(for: ref, after: more ? portableCursor : nil)
        guard !Task.isCancelled, !isClosed, request == loadGeneration, drawing.reference == ref else { return }
        portable += page.entries.filter { entry in !portable.contains { $0.archive == entry.archive && $0.run == entry.run } }
        portableCursor = page.next
      }
    } catch { if !Task.isCancelled, !isClosed, request == loadGeneration { failure = error.localizedDescription } }
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
