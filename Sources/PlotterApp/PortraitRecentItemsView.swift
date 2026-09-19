import ImageIO
import PlotterModel
import SwiftUI

struct PortraitPhotoStrip: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle

  private var bursts: [CaptureGroup] {
    var seen: Set<UUID> = []
    return model.recentPhotos.compactMap { photo in
      guard seen.insert(photo.captureSessionID).inserted else { return nil }
      return CaptureGroup(id: photo.captureSessionID,
        photos: model.recentPhotos.filter { $0.captureSessionID == photo.captureSessionID })
    }
  }

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(bursts) { burst in
          HStack(spacing: 4) {
            ForEach(burst.photos) { photo in
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
              .contextMenu {
                Button("Delete Frame", role: .destructive) {
                  model.removePhoto(photo.id, strokeStyle: strokeStyle)
                }
                Button("Delete Burst", role: .destructive) {
                  model.removeCaptureSession(photo.captureSessionID, strokeStyle: strokeStyle)
                }
              }
            }
          }
          .padding(3)
          .overlay { RoundedRectangle(cornerRadius: 5).stroke(.quaternary) }
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Capture burst, \(burst.photos.count) frames")
        }
      }.padding(.horizontal, 1)
    }
    .scrollIndicators(.hidden)
    .frame(height: 48)
    .accessibilityIdentifier("portrait.frames")
  }

  private struct CaptureGroup: Identifiable {
    let id: UUID
    let photos: [PortraitPhoto]
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
