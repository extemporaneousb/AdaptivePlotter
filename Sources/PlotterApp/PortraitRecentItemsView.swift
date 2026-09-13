import ImageIO
import PlotterModel
import SwiftUI

struct PortraitPhotoStrip: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var body: some View {
    if !model.recentPhotos.isEmpty {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Button { model.movePhoto(by: -1, strokeStyle: strokeStyle) } label: {
            Image(systemName: "chevron.left").frame(minWidth: 24, minHeight: 24)
          }.accessibilityLabel("Previous frame, same style")
            .keyboardShortcut(.leftArrow, modifiers: [.option])
          Text(model.framePosition).font(.caption).monospacedDigit()
          Button { model.movePhoto(by: 1, strokeStyle: strokeStyle) } label: {
            Image(systemName: "chevron.right").frame(minWidth: 24, minHeight: 24)
          }.accessibilityLabel("Next frame, same style")
            .keyboardShortcut(.rightArrow, modifiers: [.option])
          Spacer(minLength: 0)
        }
        Text("Same style · ⌥← / ⌥→ to browse frames").font(.caption2).foregroundStyle(.secondary)
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 10) {
            ForEach(model.recentPhotos) { photo in
              VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                  Button { model.selectPhoto(photo.id, strokeStyle: strokeStyle) } label: {
                    PortraitPhotoThumbnail(data: photo.data, id: photo.id)
                      .frame(width: 104, height: 100)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Select \(photo.label)")
                  .overlay { Rectangle().stroke(model.selectedPhotoID == photo.id ? Color.accentColor : .clear, lineWidth: 3) }
                  Button { model.removePhoto(photo.id, strokeStyle: strokeStyle) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                      .frame(width: 26, height: 26).background(.regularMaterial, in: Circle())
                  }
                  .buttonStyle(.plain).padding(4)
                  .accessibilityLabel("Remove \(photo.label)")
                }
                Text(photo.label).font(.caption2).lineLimit(1).frame(width: 104)
              }
            }
          }.padding(3)
        }
        Text("Recent frames: up to 24 / 32 MB this session. × removes this recent frame; retained drawings keep their own source.")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

struct PortraitPhotoThumbnail: View {
  let data: Data
  let id: UUID
  @State private var image: CGImage?
  var body: some View {
    Group {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else { Color.secondary.opacity(0.1) }
    }
    .task(id: id) {
      let data = data
      let decoded = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 208,
        ] as CFDictionary)
      }.value
      if !Task.isCancelled { image = decoded }
    }
  }
}

struct PortraitSketchStrip: View {
  let collection: PortraitSketchCollection
  var body: some View {
    if !collection.sketches.isEmpty {
      VStack(alignment: .leading, spacing: 5) {
        Text("Retained drawings · \(collection.sketches.count)").font(.caption).foregroundStyle(.secondary)
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 10) {
            ForEach(collection.sketches) { sketch in
              VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                  Button { collection.selectedID = sketch.id } label: {
                    PortraitProgramPreview(program: sketch.program).frame(width: 140, height: 150)
                  }.buttonStyle(.plain).accessibilityLabel("Select saved \(sketch.title)")
                    .overlay { Rectangle().stroke(collection.selectedID == sketch.id ? Color.accentColor : .clear, lineWidth: 3) }
                  Menu {
                    Button("Delete This Retained Drawing", role: .destructive) {
                      collection.remove(sketch.id)
                    }
                    Button("Delete Source and All Its Retained Drawings", role: .destructive) {
                      collection.deleteSource(sketch.candidate.sourceSHA256)
                    }
                  } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                      .frame(width: 26, height: 26).background(.regularMaterial, in: Circle())
                  }.menuStyle(.borderlessButton).fixedSize().padding(4)
                    .accessibilityLabel("Manage retained \(sketch.title)")
                }
                Text(sketch.title).font(.caption2).lineLimit(2).frame(width: 140, alignment: .leading)
                Text(retentionSummary(for: sketch.id)).font(.caption2).foregroundStyle(.secondary)
                  .frame(width: 140, alignment: .leading)
              }
            }
          }.padding(3)
        }
        Text("Deleting a retained drawing removes its payload from future datasets. Deleting its source removes every retained drawing from that source. Earlier record identities remain as deletion history.")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private func retentionSummary(for id: String) -> String {
    guard let entry = collection.entries.first(where: { $0.id == id }) else { return "" }
    var labels: [String] = []
    for event in entry.reasons {
      let label: String
      switch event.reason {
      case .shortlisted: label = "Shortlisted"
      case .rated: label = "Rated"
      case .projectionAccepted: label = "Accepted on plotter video"
      case .physicalAttempt: label = "Physical attempt"
      }
      if !labels.contains(label) { labels.append(label) }
    }
    return labels.joined(separator: " · ")
  }
}
