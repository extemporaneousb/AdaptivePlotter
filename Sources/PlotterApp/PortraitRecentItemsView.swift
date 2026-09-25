import ImageIO
import PlotterModel
import SwiftUI

struct PortraitPhotoStrip: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        Text("Photos").font(.caption).foregroundStyle(.secondary)
        ForEach(model.browsablePhotos) { photo in
          Button { model.selectPhoto(photo.id, strokeStyle: strokeStyle) } label: {
            PortraitPhotoThumbnail(data: photo.data, id: photo.id)
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
      }.padding(.horizontal, 1)
    }
    .scrollIndicators(.hidden)
    .frame(height: 48)
    .accessibilityIdentifier("portrait.recentPhotos")
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
