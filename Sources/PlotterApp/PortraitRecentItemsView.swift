import ImageIO
import PlotterModel
import SwiftUI

struct PortraitPhotoStrip: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle

  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 8) {
        Text("Photos").font(.caption).foregroundStyle(.secondary)
        ForEach(model.photoListItems) { photo in
          Button { model.selectPhoto(photo.id, strokeStyle: strokeStyle) } label: {
            PortraitBrowsablePhotoThumbnail(model: model, id: photo.id)
              .frame(width: 40, height: 40)
              .background(.black.opacity(0.05))
              .overlay {
                RoundedRectangle(cornerRadius: 3)
                  .stroke(model.selectedPhotoID == photo.id ? Color.accentColor : .clear, lineWidth: 2)
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Select \(photo.label)")
          .help(photo.label)
          .contextMenu {
            if model.recentPhotos.contains(where: { $0.id == photo.id }) {
              Button("Remove Recent Photo", role: .destructive) {
                model.removePhoto(photo.id, strokeStyle: strokeStyle)
              }
              Text("Retained attempts keep their source")
            } else {
              Button("Delete Source and All Attempts", role: .destructive) {
                model.deleteRetainedSource(photo.id, strokeStyle: strokeStyle)
              }
            }
          }
        }
        if model.sketches.photoHasMore || model.sketches.photoBrowserState == .loading {
          Button {
            Task { await model.sketches.loadMorePhotos() }
          } label: {
            if model.sketches.photoBrowserState == .loading { ProgressView().controlSize(.small) }
            else { Label("More Photos", systemImage: "ellipsis") }
          }
          .buttonStyle(.plain)
          .task(id: model.sketches.photoPageRevision) {
            await model.sketches.loadMorePhotos()
          }
        }
        if case .failed(let reason) = model.sketches.photoBrowserState {
          Button("Retry Photos") { Task { await model.sketches.loadMorePhotos() } }
            .help(reason)
        }
      }.padding(.horizontal, 1)
    }
    .scrollIndicators(.hidden)
    .frame(height: 48)
    .accessibilityIdentifier("portrait.recentPhotos")
  }
}

/// A tile owns only its small decoded thumbnail, never a cached original.
/// LazyHStack starts this task only when the tile enters its visible region.
private struct PortraitBrowsablePhotoThumbnail: View {
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
