import PortraitArtists
import DrawingLibrary
import PortraitCore
import PortraitStudioUI
import ImageIO
import PlotterModel
import PlotterRuntime
import SwiftUI

/// Browsing reads compact metadata. Only an explicit selection materializes its verified drawing.
struct DrawingReviewerView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  var showOnPlotter: ((Drawing) async -> String?)? = nil
  @State private var entries: [DrawingLibraryEntry] = []
  @State private var cursor: DrawingLibraryCursor?
  @State private var selectedRef: DrawingRef?
  @State private var drawing: Drawing?
  @State private var failure: String?
  @State private var originalPixels = false
  private var library: DrawingLibrary { application.portraitStudio.library }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Drawings").font(.title2)
        Spacer()
        Button("Close", action: close).keyboardShortcut(.cancelAction)
      }
      HSplitView {
        VStack {
          List(entries, id: \.reference, selection: $selectedRef) { entry in
            VStack(alignment: .leading) {
              Text(entry.title ?? "Drawing")
              Text("\(entry.strokeCount) strokes").font(.caption).foregroundStyle(.secondary)
            }.tag(entry.reference)
          }
          if cursor != nil { Button("Load More") { Task { await loadPage(reset: false) } } }
        }.frame(minWidth: 230)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let drawing, let ref = drawing.reference {
              Text(ref.revision.uuidString).font(.caption).textSelection(.enabled)
              PortraitPlaneProgramPreview(preview: referencePreview(drawing.program)).frame(height: 245)
              Button("Send to Drawing") { Task { failure = await showOnPlotter?(drawing) } }
              let records = application.drawingReviewRecords.filter {
                $0.attemptEvidence?.intent.context.candidate?.contentHash.description == ref.digest.description
              }
              if records.isEmpty { Text("No retained runs for this drawing.").foregroundStyle(.secondary) }
              ForEach(records, id: \.recordID) { record in
                Text("Run \(record.runID.rawValue)").font(.headline)
                Text(String(describing: record.executionDisposition)).font(.caption)
                if let attempt = record.attemptEvidence {
                  let media = attempt.baselines + attempt.progressFrames.map(\.media) + attempt.terminalFrames
                  ForEach(Array(media.enumerated()), id: \.offset) { _, reference in
                    DrawingReviewRetainedPhoto(application: application, reference: reference,
                      runID: record.runID, originalPixels: originalPixels).frame(height: 240)
                  }
                }
                DrawingReviewNotes(application: application, scope: .run(record.runID))
              }
              DrawingReviewNotes(application: application, scope: .drawing(ref.digest.description))
              Toggle("Original image pixels", isOn: $originalPixels)
            } else { Text("Select a drawing.").foregroundStyle(.secondary) }
          }.padding()
        }
      }
      if let failure { Text(failure).foregroundStyle(.red) }
    }.padding().frame(minWidth: 800, minHeight: 600)
      .task { await loadPage(reset: true) }
      .task(id: selectedRef) {
        drawing = nil
        guard let ref = selectedRef else { return }
        do {
          let loaded = try await library.drawing(ref)
          guard !Task.isCancelled, selectedRef == ref else { return }
          drawing = loaded
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
      }
  }
  private func loadPage(reset: Bool) async {
    do {
      let page = try await library.drawings(limit: 50, after: reset ? nil : cursor)
      entries = reset ? page.entries : entries + page.entries
      cursor = page.next
    } catch { failure = error.localizedDescription }
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

private func referencePreview(_ program: DrawingProgram) -> PortraitPlanePreview {
  PortraitPlanePreviewSource().resolve(program: program, nominalWidth: program.strokes.first?.style.nominalLineWidth ?? 0.4)
}
private func reviewPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
  VStack(alignment: .leading, spacing: 5) {
    Text(title).font(.caption).foregroundStyle(.secondary)
    content().frame(maxWidth: .infinity, maxHeight: .infinity).background(.white).border(.quaternary)
  }.frame(maxWidth: .infinity, maxHeight: .infinity)
}
