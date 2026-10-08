import ImageIO
import PlotterModel
import PlotterRuntime
import SwiftUI

/// The library service owns admission and ancestry. Browsing only selects its
/// generation-bound projection; it never joins raw evidence or authorizes motion.
struct DrawingReviewerView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  var showOnPlotter: ((SavedDrawing) async -> String?)? = nil
  var initialPhotoID: UUID? = nil
  var inspectInStudio: ((PortraitDrawingIdentity) async -> String?)? = nil
  @State private var filter = PortraitLibraryFilter.allPhotos
  @State private var photos: [PortraitLibraryPhoto] = []
  @State private var works: [PortraitLibraryWork] = []
  @State private var cursor: PortraitLibraryCursor?
  @State private var selectedItem: PortraitLibraryBrowseItem?
  @State private var detail: PortraitLibrarySelection?
  @State private var selectedDrawing: SavedDrawing?
  @State private var selectedWorkID: String?
  @State private var originalPixels = false
  @State private var busy = false
  @State private var loading = false
  @State private var failure: String?
  @State private var pageRevision = 0
  @State private var loadedFilter: PortraitLibraryFilter?
  @State private var selectionLoading = false

  private var library: PortraitSketchCollection { application.portraitStudio.sketches }
  private var drawing: PortraitLibraryDrawing? { detail?.selectedDrawing }
  private var work: PortraitLibraryWork? {
    detail?.works.first { $0.id == selectedWorkID }
  }
  private var availableWorks: [PortraitLibraryWork] {
    guard let drawing else { return detail?.works ?? [] }
    return detail?.works.filter { $0.drawingID == drawing.id } ?? []
  }
  private var noteScope: DrawingReviewNoteScope? {
    if let work { return .run(work.runID) }
    return drawing.map { .drawing($0.identity.candidateID) }
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Portrait Library").font(.title2)
        StudioHelpButton("Portrait Library", text: "Every retained source capture has its own identity, including captures without drawings. Plotted works have validated photo and drawing ancestry plus executed or possible-ink history. Prepared requests without ink remain drawing history. Controller outcome, retained photographs and physical ink are independent. Browsing changes no live run or paper facts.")
        Spacer()
        Picker("Image size", selection: $originalPixels) {
          Text("Fit").tag(false); Text("100%").tag(true)
        }.pickerStyle(.segmented).frame(width: 140)
        Button("Close", action: close).keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("drawing.reviewer.close")
      }
      HStack {
        Picker("Browse", selection: $filter) {
          ForEach(PortraitLibraryFilter.allCases, id: \.self) { value in
            Text(PortraitLibraryBrowsePresentation.filterTitle(value)).tag(value)
          }
        }.frame(maxWidth: 360).accessibilityIdentifier("drawing.reviewer.filter")
        Text("\(filter == .plottedWorks ? works.count : photos.count) loaded")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if cursor != nil {
          Button("Load More") { Task { await loadPage(reset: false) } }.disabled(loading)
            .accessibilityIdentifier("drawing.reviewer.more")
        }
        Button("Refresh") { pageRevision += 1 }.disabled(loading)
      }
      HSplitView {
        List(selection: $selectedItem) {
          ForEach(photos) { photo in
            HStack(spacing: 8) {
              PortraitBrowsablePhotoThumbnail(model: application.portraitStudio, id: photo.id)
                .frame(width: 40, height: 48)
              VStack(alignment: .leading, spacing: 3) {
                Text(PortraitLibraryBrowsePresentation.photoTitle(photo)).lineLimit(2)
                Text("\(photo.drawingCount) drawings · \(photo.plottedWorkCount) plotted works")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }.tag(PortraitLibraryBrowseItem.photo(photo.id))
              .help("\(photo.reference.label)\nCapture \(photo.id.uuidString)\n\(PortraitLibraryBrowsePresentation.captureDescription(photo))")
              .accessibilityIdentifier("drawing.reviewPhoto.\(photo.id)")
          }
          ForEach(works) { value in
            HStack(alignment: .top, spacing: 8) {
              PortraitLibraryWorkThumbnail(application: application, work: value)
                .frame(width: 60, height: 66)
              VStack(alignment: .leading, spacing: 3) {
                Text(PortraitLibraryBrowsePresentation.workTitle(value)).lineLimit(2)
                Text(PortraitLibraryBrowsePresentation.workDate(value)).font(.caption)
                Text(PortraitLibraryBrowsePresentation.workStatus(value)).font(.caption).foregroundStyle(.secondary)
              }
            }.tag(PortraitLibraryBrowseItem.work(value.id))
              .help("Run \(value.id)\nPhoto \(value.photoID.uuidString)\nDrawing \(value.drawingID)\n\(value.status)")
              .accessibilityIdentifier("drawing.reviewWork.\(value.id)")
          }
        }.frame(minWidth: 240, idealWidth: 290, maxWidth: 360)
          .accessibilityIdentifier("drawing.reviewer.items")
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let detail {
              Text(detail.photo.reference.label).font(.headline)
              Text("Capture \(detail.photo.id.uuidString) · \(PortraitLibraryBrowsePresentation.captureDescription(detail.photo))")
                .font(.caption).textSelection(.enabled)
              Text("\(detail.photo.drawingCount) drawings · \(detail.photo.plottedWorkCount) plotted works")
                .font(.caption).foregroundStyle(.secondary)
              HStack(alignment: .top, spacing: 12) {
                reviewPanel("Source photograph") {
                  PortraitLibrarySourcePhoto(model: application.portraitStudio, photoID: detail.photo.id,
                    sourceSHA256: detail.photo.reference.sourceSHA256, originalPixels: originalPixels)
                }
                reviewPanel("Exact drawing reference") {
                  if let program = detail.program {
                    PortraitPlaneProgramPreview(preview: referencePreview(program))
                  } else {
                    ContentUnavailableView("Select a drawing", systemImage: "pencil.line",
                      description: Text(detail.drawings.isEmpty ? "This capture has no retained drawings." : "Choose a retained drawing below."))
                  }
                }
              }.frame(height: 245)
              if !detail.drawings.isEmpty {
                Picker("Drawing", selection: Binding(get: { detail.selectedDrawing?.identity }, set: { identity in
                  if let identity { selectedItem = .drawing(identity) }
                })) {
                  Text("Select drawing").tag(nil as PortraitDrawingIdentity?)
                  ForEach(detail.drawings) { value in
                    Text(PortraitLibraryBrowsePresentation.drawingTitle(value)).tag(Optional(value.identity))
                  }
                }.accessibilityIdentifier("drawing.reviewer.drawings")
              }
              if let drawing {
                Text("Drawing \(drawing.identity.candidateID)").font(.caption2).textSelection(.enabled)
                if !drawing.isRenderable {
                  Text("Historical exact program retained. Recipe and analyzed raster are unknown; regeneration and Portrait Studio inspection are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
              if !availableWorks.isEmpty {
                Picker("Run history", selection: $selectedWorkID) {
                  Text("Select run").tag(nil as String?)
                  ForEach(availableWorks) { value in
                    Text(PortraitLibraryBrowsePresentation.workDate(value) + " · " + PortraitLibraryBrowsePresentation.workStatus(value)).tag(Optional(value.id))
                  }
                }.accessibilityIdentifier("drawing.reviewer.runs")
              } else { Text("No retained runs for this selection.").font(.caption).foregroundStyle(.secondary) }
              if let work {
                PortraitLibraryWorkReview(application: application, work: work, originalPixels: originalPixels)
                  .id(work.id)
              }
              if let noteScope { DrawingReviewNotes(application: application, scope: noteScope).id(noteScope) }
            } else if library.libraryState == .loading {
              ProgressView("Reconciling portrait history…")
            } else if case .failed(let reason) = library.libraryState {
              ContentUnavailableView("Portrait library unavailable", systemImage: "exclamationmark.triangle", description: Text(reason))
            } else if loading || selectionLoading { ProgressView("Loading portrait library…") }
            else { ContentUnavailableView("Select a photo or plotted work", systemImage: "photo.on.rectangle") }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      actionBar
      if let failure {
        HStack { Text(failure).font(.caption).foregroundStyle(.red); Button("Retry Library") { pageRevision += 1 } }
      }
    }.padding(18).frame(minWidth: 1000, minHeight: 700)
      .task(id: PortraitLibraryBrowseRequest(filter: filter, revision: pageRevision)) {
        await application.portraitStudio.loadPhotoBrowser()
        await library.awaitLibrarySynchronization()
        await loadPage(reset: true)
      }
      .task(id: selectedItem) { await loadSelection() }
      .onChange(of: library.libraryState) { _, state in
        if state != .saved {
          detail = nil; selectedDrawing = nil; photos = []; works = []; cursor = nil
          if case .failed(let reason) = state { failure = reason }
        }
        if state == .saved { pageRevision += 1 }
      }
      .accessibilityIdentifier("drawing.reviewer")
  }

  private var actionBar: some View {
    HStack {
      if let work {
        Button(work.recordID == nil ? "Dismiss Unfinished Run" : "Delete Run Review", role: .destructive) {
          perform {
            do {
              if let id = work.recordID { try await application.deleteDrawingReview(recordID: id) }
              else { try await application.dismissDrawingAttemptReview(runID: work.runID) }
              await library.awaitLibrarySynchronization()
              return nil
            } catch { return error.localizedDescription }
          }
        }.disabled(busy)
        StudioHelpButton("Remove review", text: "Hides review through the canonical evidence tombstone. Original attempts, possible-ink and no-redraw facts and shared media remain retained. This never declares paper clear.")
      }
      if let photo = detail?.photo {
        Button("Delete Photo and Its Drawings", role: .destructive) {
          perform { library.deleteSource(photoID: photo.id); await library.awaitPersistence(); return nil }
        }.disabled(busy).accessibilityIdentifier("drawing.reviewer.deletePhoto")
      }
      if let drawing, drawing.isRenderable {
        Button("Delete Drawing", role: .destructive) {
          perform { library.deleteDrawing(drawing.identity); await library.awaitPersistence(); return nil }
        }.disabled(busy)
        if let saved = selectedDrawing, saved.sourcePhotoID == drawing.identity.photoID {
          if !drawing.summary.isSaved {
            Button("Save Drawing") { perform { await library.saveDrawing(saved) } }.disabled(busy)
          }
          if let inspectInStudio {
            Button("Inspect in Portrait Studio") {
              perform {
                let error = await inspectInStudio(drawing.identity)
                if error == nil { close() }
                return error
              }
            }.disabled(busy)
          }
          if let showOnPlotter {
            Button("Send to Drawing", systemImage: "video") {
              perform {
                let error = await showOnPlotter(saved)
                if error == nil { close() }
                return error
              }
            }.disabled(busy).accessibilityIdentifier("drawing.reviewer.showOnPlotter")
          }
        }
      }
      Spacer()
      if busy || loading { ProgressView().controlSize(.small) }
    }.controlSize(.small)
  }

  @MainActor private func loadPage(reset: Bool) async {
    guard reset || cursor != nil else { return }
    loading = true; failure = nil
    let requestedFilter = filter
    if reset { photos = []; works = []; cursor = nil; detail = nil; selectedDrawing = nil }
    defer { if !Task.isCancelled { loading = false } }
    do {
      let page = try await library.librarySnapshot(filter: requestedFilter, after: reset ? nil : cursor, limit: 100)
      try Task.checkCancellation()
      guard filter == requestedFilter else { return }
      photos += page.photos; works += page.works; cursor = page.next
      if reset {
        // A retained selection can lie beyond the current first page. Validate
        // it with the same service selection read, never first-page membership.
        selectedItem = PortraitLibraryBrowsePresentation.selectionAfterReload(current: selectedItem,
          previousFilter: loadedFilter, filter: requestedFilter, initialPhotoID: initialPhotoID,
          photos: photos, works: works)
        loadedFilter = requestedFilter
        await loadSelection()
      }
    } catch { if !Task.isCancelled { failure = error.localizedDescription } }
  }

  @MainActor private func loadSelection() async {
    let requested = selectedItem
    detail = nil; selectedDrawing = nil; selectedWorkID = nil
    guard let requested else { return }
    selectionLoading = true; failure = nil
    defer { if requested == selectedItem { selectionLoading = false } }
    do {
      let value: PortraitLibrarySelection
      switch requested {
      case .photo(let id): value = try await library.librarySelection(photoID: id)
      case .work(let id): value = try await library.librarySelection(workID: id)
      case .drawing(let identity): value = try await library.librarySelection(drawingIdentity: identity)
      }
      try Task.checkCancellation()
      guard requested == selectedItem else { return }
      if filter == .photosWithPlottedWorks && value.photo.plottedWorkCount == 0
        || filter == .photosWithoutPlottedWorks && value.photo.plottedWorkCount > 0 {
        selectedItem = photos.first.map { .photo($0.id) }
        return
      }
      detail = value
      selectedWorkID = value.selectedWorkID
      if case .work(let id) = requested { selectedWorkID = id }
      if let selected = value.selectedDrawing, selected.isRenderable {
        let saved = try await library.drawingForBrowsing(selected.identity)
        try Task.checkCancellation()
        guard requested == selectedItem else { return }
        selectedDrawing = saved
      }
    } catch { if !Task.isCancelled, requested == selectedItem { failure = error.localizedDescription } }
  }

  private func perform(_ action: @escaping @MainActor () async -> String?) {
    busy = true; failure = nil
    Task { @MainActor in
      failure = await action(); busy = false
      if failure == nil { pageRevision += 1 }
    }
  }
}

private struct PortraitLibraryBrowseRequest: Hashable {
  let filter: PortraitLibraryFilter
  let revision: Int
}

private struct PortraitLibrarySourcePhoto: View {
  let model: PortraitStudioModel
  let photoID: UUID
  let sourceSHA256: String
  let originalPixels: Bool
  @State private var photo: PortraitPhoto?
  @State private var failure: String?
  var body: some View {
    Group {
      if let photo {
        DrawingReviewSource(data: photo.data, sourceSHA256: sourceSHA256, originalPixels: originalPixels)
      } else if let failure { ContentUnavailableView("Photo unavailable", systemImage: "photo", description: Text(failure)) }
      else { ProgressView() }
    }.task(id: photoID) {
      photo = nil; failure = nil
      do {
        let value = try await model.photoForBrowsing(photoID)
        try Task.checkCancellation(); photo = value
      } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
  }
}

/// Visible rows request only one selected raw frame, then retain a small image.
private struct PortraitLibraryWorkThumbnail: View {
  let application: PlotterApplicationRuntime
  let work: PortraitLibraryWork
  @State private var image: CGImage?
  @State private var failed = false
  private var media: PortraitLibraryMedia? {
    guard case .media(let id) = PortraitLibraryBrowsePresentation.thumbnailChoice(work.media) else { return nil }
    return work.media.first { $0.id == id }
  }
  var body: some View {
    VStack(spacing: 2) {
      Group {
        if let media {
          if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
          else { Image(systemName: failed ? "exclamationmark.triangle" : "photo") }
        } else {
          PortraitBrowsablePhotoThumbnail(model: application.portraitStudio, id: work.photoID)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(media.map { PortraitLibraryBrowsePresentation.mediaLabel($0) } ?? "Source")
        .font(.caption2).foregroundStyle(.secondary)
    }.task(id: media?.id) {
      image = nil; failed = false
      guard let media else { return }
      do {
        let frame = try await application.drawingReviewImage(media.reference, runID: work.runID)
        try Task.checkCancellation()
        let decoded = await Task.detached(priority: .utility) {
          guard let original = FrameImageFactory.image(from: frame.frame) else { return nil as CGImage? }
          let scale = min(1, 144.0 / Double(max(original.width, original.height)))
          let width = max(1, Int(Double(original.width) * scale))
          let height = max(1, Int(Double(original.height) * scale))
          guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil as CGImage? }
          context.interpolationQuality = .medium
          context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
          return context.makeImage()
        }.value
        try Task.checkCancellation(); image = decoded; failed = decoded == nil
      } catch { if !Task.isCancelled { failed = true } }
    }.onDisappear { image = nil }
  }
}

private struct PortraitLibraryWorkReview: View {
  let application: PlotterApplicationRuntime
  let work: PortraitLibraryWork
  let originalPixels: Bool
  @State private var mediaID: String?
  private var media: PortraitLibraryMedia? { work.media.first { $0.id == mediaID } }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Run \(work.id)").font(.headline).textSelection(.enabled)
      Text(PortraitLibraryBrowsePresentation.workTitle(work)).font(.caption)
      Text(PortraitLibraryBrowsePresentation.workStatus(work)).font(.caption)
      Text(work.recordedAt.map { "Recorded " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Run time unknown").font(.caption)
      Text("Controller status: \(work.status)").font(.caption).textSelection(.enabled)
      Text(work.executedOrPossibleInk ? "Executed or possible ink retained. Ink coverage requires visual evidence." : "Prepared history; no executed or possible-ink marker retained.")
        .font(.caption).foregroundStyle(.secondary)
      Text("\(work.media.filter(\.isAvailable).count)/\(work.media.count) photographs available · \(work.media.filter { $0.stage.hasPrefix("terminal-") }.count) terminal references")
        .font(.caption).foregroundStyle(.secondary)
      if !work.media.isEmpty {
        Picker("Retained photograph", selection: $mediaID) {
          Text("Select photograph").tag(nil as String?)
          ForEach(work.media) { value in
            Text(value.stage + (value.isAvailable ? "" : " · unavailable")).tag(Optional(value.id))
          }
        }
      }
      if let media {
        reviewPanel(media.stage) {
          if media.isAvailable {
            DrawingReviewRetainedPhoto(application: application, reference: media.reference,
              runID: work.runID, originalPixels: originalPixels).id(media.id)
          } else {
            ContentUnavailableView("Photograph unavailable", systemImage: "photo",
              description: Text(media.unavailableReason ?? "Retained media is unavailable."))
          }
        }.frame(height: 280)
      } else {
        Text("No photograph selected. A controller result does not establish photograph completeness or observed ink.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.onAppear {
      if case .media(let id) = PortraitLibraryBrowsePresentation.thumbnailChoice(work.media) { mediaID = id }
      else { mediaID = work.media.first?.id }
    }
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
