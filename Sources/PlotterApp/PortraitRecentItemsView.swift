import ImageIO
import PlotterModel
import SwiftUI

struct PortraitPhotoStrip: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle

  @State private var photos: [PortraitLibraryPhoto] = []
  @State private var cursor: PortraitLibraryCursor?
  @State private var loading = false
  @State private var failure: String?

  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 8) {
        Text("Photos").font(.caption).foregroundStyle(.secondary)
        ForEach(photos) { photo in
          Button { model.selectPhoto(photo.id, strokeStyle: strokeStyle) } label: {
            PortraitBrowsablePhotoThumbnail(model: model, id: photo.id)
              .frame(width: 40, height: 40)
              .background(.black.opacity(0.05))
              .overlay {
                RoundedRectangle(cornerRadius: 3)
                  .stroke(model.selectedPhotoID == photo.id ? Color.accentColor : .clear, lineWidth: 2)
              }.contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityLabel("Select \(photo.reference.label)")
            .help("\(photo.reference.label) · \(PortraitLibraryBrowsePresentation.captureDescription(photo)) · \(photo.drawingCount) drawings · \(photo.plottedWorkCount) plotted works · \(photo.id)")
            .contextMenu {
              Button("Delete Photo and Its Drawings", role: .destructive) {
                model.deleteRetainedSource(photo.id, strokeStyle: strokeStyle)
                Task { await model.sketches.awaitPersistence(); await load(reset: true) }
              }
            }
        }
        if cursor != nil {
          Button("More Photos", systemImage: "ellipsis") { Task { await load(reset: false) } }
            .buttonStyle(.plain).disabled(loading)
            .task(id: cursor?.offset) { await load(reset: false) }
        }
        if loading { ProgressView().controlSize(.small) }
        if let failure {
          Button("Retry Photos") { Task { await load(reset: true) } }.help(failure)
        }
      }.padding(.horizontal, 1)
    }.scrollIndicators(.hidden).frame(height: 48)
      .task { await model.loadPhotoBrowser(); await model.sketches.awaitLibrarySynchronization(); await load(reset: true) }
      .onChange(of: model.sketches.libraryState) { _, state in
        if state == .loading { photos = []; cursor = nil }
        if state == .saved { Task { await load(reset: true) } }
      }
      .onChange(of: model.sketches.photoPageRevision) { Task { await load(reset: true) } }
      .accessibilityIdentifier("portrait.recentPhotos")
  }

  @MainActor private func load(reset: Bool) async {
    guard !loading, reset || cursor != nil else { return }
    loading = true; failure = nil
    defer { loading = false }
    do {
      let page = try await model.sketches.librarySnapshot(filter: .allPhotos, after: reset ? nil : cursor, limit: 100)
      try Task.checkCancellation()
      if reset { photos = page.photos } else { photos += page.photos }
      cursor = page.next
    } catch { if !Task.isCancelled { failure = error.localizedDescription } }
  }
}

/// A tile owns only its small decoded thumbnail, never a cached original.
/// LazyHStack starts this task only when the tile enters its visible region.
struct PortraitBrowsablePhotoThumbnail: View {
  let model: PortraitStudioModel
  let id: UUID
  @State private var image: CGImage?
  @State private var failure: String?
  var body: some View {
    Group {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else if failure != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
      else { Color.secondary.opacity(0.1) }
    }
    .help(failure ?? "")
    .task(id: id) {
      do {
        let photo = try await model.photoForBrowsing(id)
        let decoder = Task.detached(priority: .utility) {
          guard let source = CGImageSourceCreateWithData(photo.data as CFData, nil) else { return nil as CGImage? }
          return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 208,
          ] as CFDictionary)
        }
        let decoded = await withTaskCancellationHandler { await decoder.value } onCancel: { decoder.cancel() }
        guard !Task.isCancelled else { return }
        image = decoded
        if decoded == nil { failure = "The retained source image could not be decoded." }
      } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    .onDisappear { image = nil }
  }
}

struct PortraitPhotoThumbnail: View {
  let data: Data
  let id: UUID
  var maximumPixelSize = 208
  @State private var image: CGImage?
  var body: some View {
    Group {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else { Color.secondary.opacity(0.1) }
    }
    .task(id: id) {
      let data = data
      let maximumPixelSize = maximumPixelSize
      let decoded = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary)
      }.value
      if !Task.isCancelled { image = decoded }
    }
  }
}
