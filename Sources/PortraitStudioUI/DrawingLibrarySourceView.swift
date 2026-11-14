import DrawingLibrary
import Foundation
import PortraitCore
import PortraitLibrary
import SwiftUI
import AppKit

@MainActor
package struct DrawingLibrarySourceView: View {
  package let sketches: PortraitSketchCollection
  @Binding package var route: DrawingLibraryRoute
  package let openStudio: (PhotoRef) async -> String?
  @State private var photos: [DrawingLibraryPhotoEntry] = []
  @State private var cursor: DrawingLibraryPhotoCursor?
  @State private var inputs: [DrawingLibraryInputEntry] = []
  @State private var inputCursor: DrawingLibraryInputCursor?
  @State private var metadata = DrawingLibraryPhotoMetadata()
  @State private var pixels: Data?
  @State private var failure: String?
  @State private var loadedPhoto: PhotoRef?
  @State private var authoringUnavailable: String?
  @State private var exportPanel: NSSavePanel?
  @Environment(\.drawingPresentationPolicy) private var presentationPolicy
  package var body: some View {
    HSplitView {
      VStack {
        List(photos, id: \.reference, selection: Binding(get: { route.photo }, set: { ref in
          if route.selectPhoto(ref) { sketches.clearSelection() }
        })) { photo in
          HStack(spacing: 8) {
            DrawingLibraryThumbnail(library: sketches.library, source: .photo(photo.reference)).frame(width: 48, height: 56)
            VStack(alignment: .leading) {
            Text((loadedPhoto == photo.reference ? metadata.title : photo.metadata.title) ?? "Photo")
            Text(photo.sortDate?.formatted(date: .abbreviated, time: .shortened) ?? "Date unknown")
              .font(.caption).foregroundStyle(.secondary)
            }
          }.tag(photo.reference)
        }.listStyle(.sidebar)
        if cursor != nil { Button("More Photos") { Task { await loadPhotos(more: true) } } }
      }.frame(minWidth: 210, idealWidth: 240)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let ref = route.photo {
            FlowAuthoringImage(data: loadedPhoto == route.photo ? pixels : nil, identity: "library-photo:" + (route.photo?.digest.description ?? "none"), maximumDimension: 640).frame(height: 160)
            Button("Export Photo") { Task { await exportPhoto(ref) } }
              .help("Export the original verified Photo publication without changing its pixels or metadata.")
            if loadedPhoto == ref {
              TextField("Title (optional)", text: field(\.title, ref: ref))
              TextField("Subject identity (optional)", text: field(\.subjectID, ref: ref))
              TextField("Photo session (optional)", text: field(\.sessionID, ref: ref))
              Toggle("Exclude from training", isOn: Binding(get: { metadata.excluded }, set: { value in
                metadata.excluded = value; save(ref, .init(excluded: value), field: "Training exclusion")
              }))
              Button("Open in Photo Booth") { Task {
                let message = await openStudio(ref)
                if route.photo == ref { failure = message }
              } }
                .disabled(authoringUnavailable != nil)
              if let authoringUnavailable { Text(authoringUnavailable).font(.caption).foregroundStyle(.secondary) }
              Text("Photo variants").font(.headline)
              Button("All Drawings for Photo") { route.input = nil; route.drawing = nil; sketches.clearSelection() }
              ForEach(inputs, id: \.reference) { input in
                Button {
                  route.input = input.reference
                  route.drawing = nil; sketches.clearSelection()
                } label: {
                  HStack(spacing: 8) {
                    DrawingLibraryThumbnail(library: sketches.library, source: .input(input.reference)).frame(width: 60, height: 64)
                    Text("Variant " + input.reference.revision.uuidString.prefix(8)).font(.caption)
                    Spacer()
                  }
                }.buttonStyle(.plain)
              }
              if inputCursor != nil { Button("More Variants") { Task { await loadInputs(ref, more: true) } } }
            }
          } else { Text("Select a Photo to browse its originals, variants and drawings.").foregroundStyle(.secondary) }
          if let failure { Text("Photo unavailable: " + failure).foregroundStyle(.red) }
        }.padding()
      }.frame(minWidth: 250, idealWidth: 280)
    }.task { await loadPhotos() }
      .task(id: route.photo) { await selectPhoto() }
      .onChange(of: presentationPolicy.modalUnavailableReason) { _, reason in if reason != nil { exportPanel?.cancel(nil) } }
  }
  private func exportPhoto(_ ref: PhotoRef) async {
    if let reason = presentationPolicy.modalUnavailableReason { failure = reason; return }
    let panel = NSSavePanel(); panel.title = "Export Photo publication"; panel.nameFieldStringValue = "Photo.zip"
    exportPanel = panel; defer { exportPanel = nil }
    guard await panel.begin() == .OK, let url = panel.url else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do { try await sketches.library.exportPhoto(ref, to: url) }
    catch { if route.photo == ref { failure = error.localizedDescription } }
  }
  private func field(_ key: WritableKeyPath<DrawingLibraryPhotoMetadata, String?>, ref: PhotoRef) -> Binding<String> {
    Binding(get: { metadata[keyPath: key] ?? "" }, set: { value in
      metadata[keyPath: key] = value.isEmpty ? nil : value
      let change = DrawingLibraryPhotoTextChange.set(value.isEmpty ? nil : value)
      let patch: DrawingLibraryPhotoMetadataPatch
      if key == \.title { patch = .init(title: change) }
      else if key == \.subjectID { patch = .init(subjectID: change) }
      else { patch = .init(sessionID: change) }
      save(ref, patch, field: key == \.title ? "Title" : (key == \.subjectID ? "Subject identity" : "Photo session"))
    })
  }
  private func save(_ ref: PhotoRef, _ patch: DrawingLibraryPhotoMetadataPatch, field: String) {
    let pending = sketches.updatePhotoMetadata(ref, patch: patch)
    Task {
      let message = await pending.value
      if route.photo == ref, let message { failure = field + ": " + message }
    }
  }
  private func loadPhotos(more: Bool = false) async {
    do {
      let page = try await sketches.library.photos(after: more ? cursor : nil)
      guard !Task.isCancelled else { return }
      photos = more ? photos + page.entries : page.entries; cursor = page.next
    } catch { if !Task.isCancelled { failure = error.localizedDescription } }
  }
  private func selectPhoto() async {
    loadedPhoto = nil; pixels = nil; inputs = []; inputCursor = nil; failure = nil
    authoringUnavailable = "Loading the exact Photo…"
    guard let ref = route.photo else { return }
    do {
      let fields = try await sketches.library.photoMetadata(ref)
      guard !Task.isCancelled, route.photo == ref else { return }
      metadata = fields; loadedPhoto = ref
      await loadInputs(ref)
      guard !Task.isCancelled, route.photo == ref else { return }
      do {
        let value = try await sketches.library.photo(ref)
        guard !Task.isCancelled, route.photo == ref else { return }
        pixels = value.assets.first(where: { $0.descriptor.asset == value.record.original && ["image/png", "image/jpeg"].contains($0.descriptor.asset.mediaType) })?.bytes
        authoringUnavailable = pixels == nil ? "Authoring unavailable for this original encoding. The retained source remains in the Library." : nil
      } catch {
        if !Task.isCancelled, route.photo == ref { authoringUnavailable = "Authoring unavailable: " + error.localizedDescription }
      }
    } catch { if !Task.isCancelled, route.photo == ref { failure = error.localizedDescription } }
  }
  private func loadInputs(_ ref: PhotoRef, more: Bool = false) async {
    do {
      let page = try await sketches.library.inputs(for: ref, after: more ? inputCursor : nil)
      guard !Task.isCancelled, route.photo == ref else { return }
      inputs = more ? inputs + page.entries : page.entries; inputCursor = page.next
    } catch { if route.photo == ref { failure = error.localizedDescription } }
  }
}
